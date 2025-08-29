using System.Collections.Concurrent;
using Microsoft.Extensions.Options;

namespace MemoryStressTester.Services;

public interface IMemoryStressService
{
    Task<MemoryAllocationResult> AllocateMemoryAsync(int megabytes, int thresholdMB);
    MemoryStatus GetMemoryStatus();
    void ClearAllocations();
    bool IsAboveThreshold(int thresholdMB);
}

public class MemoryStressService : IMemoryStressService, IDisposable
{
    private readonly ConcurrentDictionary<Guid, byte[]> _allocatedMemory;
    private readonly Timer _cleanupTimer;
    private readonly MemorySettings _settings;
    private readonly object _lock = new();
    private bool _disposed = false;

    public MemoryStressService(IOptions<MemorySettings> settings)
    {
        _settings = settings.Value;
        _allocatedMemory = new ConcurrentDictionary<Guid, byte[]>();
        
        // Cleanup timer to prevent indefinite memory growth
        _cleanupTimer = new Timer(CleanupOldAllocations, null, 
            TimeSpan.FromSeconds(_settings.CleanupIntervalSeconds), 
            TimeSpan.FromSeconds(_settings.CleanupIntervalSeconds));
    }

    public async Task<MemoryAllocationResult> AllocateMemoryAsync(int megabytes, int thresholdMB)
    {
        try
        {
            var allocationId = Guid.NewGuid();
            var startMemory = GC.GetTotalMemory(false);
            var startTime = DateTime.UtcNow;

            // Apply resource limiting if enabled
            if (_settings.EnableResourceLimiting)
            {
                // Check maximum allocation size
                if (megabytes > _settings.MaxAllocationSizeMB)
                {
                    return new MemoryAllocationResult
                    {
                        Success = false,
                        AllocationId = allocationId,
                        RequestedMB = megabytes,
                        ThresholdMB = thresholdMB,
                        CurrentMemoryMB = GetCurrentMemoryUsageMB(),
                        Message = $"Allocation size {megabytes}MB exceeds maximum allowed {_settings.MaxAllocationSizeMB}MB",
                        IsThresholdExceeded = false,
                        IsOutOfMemory = false
                    };
                }

                // Check maximum concurrent allocations
                if (_allocatedMemory.Count >= _settings.MaxConcurrentAllocations)
                {
                    return new MemoryAllocationResult
                    {
                        Success = false,
                        AllocationId = allocationId,
                        RequestedMB = megabytes,
                        ThresholdMB = thresholdMB,
                        CurrentMemoryMB = GetCurrentMemoryUsageMB(),
                        Message = $"Maximum concurrent allocations ({_settings.MaxConcurrentAllocations}) reached. Clear allocations first.",
                        IsThresholdExceeded = false,
                        IsOutOfMemory = false
                    };
                }

                // Enforce maximum allowed threshold
                var effectiveThreshold = Math.Min(thresholdMB, _settings.MaxAllowedThresholdMB);
                if (thresholdMB > _settings.MaxAllowedThresholdMB)
                {
                    thresholdMB = effectiveThreshold;
                }
            }

            // Check if we're about to exceed threshold
            var currentMemoryMB = GetCurrentMemoryUsageMB();
            if (currentMemoryMB + megabytes > thresholdMB)
            {
                return new MemoryAllocationResult
                {
                    Success = false,
                    AllocationId = allocationId,
                    RequestedMB = megabytes,
                    ThresholdMB = thresholdMB,
                    CurrentMemoryMB = currentMemoryMB,
                    Message = $"Allocation would exceed threshold of {thresholdMB}MB. Current: {currentMemoryMB}MB, Requested: {megabytes}MB",
                    IsThresholdExceeded = true
                };
            }

            // Simulate memory allocation
            await Task.Run(() =>
            {
                var bytes = new byte[megabytes * 1024 * 1024]; // Convert MB to bytes
                
                // Fill with random data to prevent optimization
                var random = new Random();
                random.NextBytes(bytes);
                
                _allocatedMemory[allocationId] = bytes;
            });

            var endMemory = GC.GetTotalMemory(false);
            var endTime = DateTime.UtcNow;

            var result = new MemoryAllocationResult
            {
                Success = true,
                AllocationId = allocationId,
                RequestedMB = megabytes,
                ActualMemoryIncreaseMB = (endMemory - startMemory) / (1024 * 1024),
                AllocationTimeMs = (endTime - startTime).TotalMilliseconds,
                ThresholdMB = thresholdMB,
                CurrentMemoryMB = GetCurrentMemoryUsageMB(),
                Message = $"Successfully allocated {megabytes}MB"
            };

            // Check if we're now above threshold after allocation
            result.IsThresholdExceeded = result.CurrentMemoryMB > thresholdMB;

            return result;
        }
        catch (OutOfMemoryException)
        {
            // Force garbage collection
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();

            return new MemoryAllocationResult
            {
                Success = false,
                RequestedMB = megabytes,
                ThresholdMB = thresholdMB,
                CurrentMemoryMB = GetCurrentMemoryUsageMB(),
                Message = "Out of memory exception occurred during allocation",
                IsOutOfMemory = true,
                IsThresholdExceeded = true
            };
        }
        catch (Exception ex)
        {
            return new MemoryAllocationResult
            {
                Success = false,
                RequestedMB = megabytes,
                ThresholdMB = thresholdMB,
                CurrentMemoryMB = GetCurrentMemoryUsageMB(),
                Message = $"Error during allocation: {ex.Message}",
                IsThresholdExceeded = true
            };
        }
    }

    public MemoryStatus GetMemoryStatus()
    {
        var totalMemory = GC.GetTotalMemory(false);
        var workingSet = Environment.WorkingSet;
        
        return new MemoryStatus
        {
            TotalAllocatedMB = totalMemory / (1024 * 1024),
            WorkingSetMB = workingSet / (1024 * 1024),
            ManagedMemoryMB = GC.GetTotalMemory(false) / (1024 * 1024),
            Generation0Collections = GC.CollectionCount(0),
            Generation1Collections = GC.CollectionCount(1),
            Generation2Collections = GC.CollectionCount(2),
            ActiveAllocations = _allocatedMemory.Count,
            LastCleanup = DateTime.UtcNow
        };
    }

    public bool IsAboveThreshold(int thresholdMB)
    {
        return GetCurrentMemoryUsageMB() > thresholdMB;
    }

    public void ClearAllocations()
    {
        lock (_lock)
        {
            _allocatedMemory.Clear();
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
        }
    }

    private long GetCurrentMemoryUsageMB()
    {
        return GC.GetTotalMemory(false) / (1024 * 1024);
    }

    private void CleanupOldAllocations(object? state)
    {
        // Remove half of the allocations periodically to prevent indefinite growth
        if (_allocatedMemory.Count > 10)
        {
            var keysToRemove = _allocatedMemory.Keys.Take(_allocatedMemory.Count / 2).ToList();
            foreach (var key in keysToRemove)
            {
                _allocatedMemory.TryRemove(key, out _);
            }
            
            GC.Collect();
        }
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            _cleanupTimer?.Dispose();
            ClearAllocations();
            _disposed = true;
        }
    }
}

public class MemoryAllocationResult
{
    public bool Success { get; set; }
    public Guid AllocationId { get; set; }
    public int RequestedMB { get; set; }
    public long ActualMemoryIncreaseMB { get; set; }
    public double AllocationTimeMs { get; set; }
    public int ThresholdMB { get; set; }
    public long CurrentMemoryMB { get; set; }
    public string Message { get; set; } = string.Empty;
    public bool IsThresholdExceeded { get; set; }
    public bool IsOutOfMemory { get; set; }
}

public class MemoryStatus
{
    public long TotalAllocatedMB { get; set; }
    public long WorkingSetMB { get; set; }
    public long ManagedMemoryMB { get; set; }
    public int Generation0Collections { get; set; }
    public int Generation1Collections { get; set; }
    public int Generation2Collections { get; set; }
    public int ActiveAllocations { get; set; }
    public DateTime LastCleanup { get; set; }
}
