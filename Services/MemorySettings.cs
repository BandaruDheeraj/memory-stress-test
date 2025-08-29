namespace MemoryStressTester.Services;

public class MemorySettings
{
    public int DefaultThresholdMB { get; set; } = 512;
    public int MaxAllowedThresholdMB { get; set; } = 2048;
    public int CleanupIntervalSeconds { get; set; } = 30;
    public int MaxAllocationSizeMB { get; set; } = 256;
    public int MaxConcurrentAllocations { get; set; } = 10;
    public bool EnableResourceLimiting { get; set; } = true;
}
