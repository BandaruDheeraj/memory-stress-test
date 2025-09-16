using Microsoft.AspNetCore.Mvc;
using MemoryStressTester.Services;

namespace MemoryStressTester.Controllers;

[ApiController]
[Route("api/[controller]")]
public class HealthController : ControllerBase
{
    private readonly IMemoryStressService _memoryService;
    private readonly ILogger<HealthController> _logger;

    public HealthController(IMemoryStressService memoryService, ILogger<HealthController> logger)
    {
        _memoryService = memoryService;
        _logger = logger;
    }

    [HttpGet]
    public IActionResult Get()
    {
        try
        {
            var status = _memoryService.GetMemoryStatus();
            
            // Simple health check - application is healthy if we can get memory status
            return Ok(new
            {
                status = "Healthy",
                timestamp = DateTime.UtcNow,
                version = "1.0.0",
                memory = new
                {
                    managedMemoryMB = status.ManagedMemoryMB,
                    workingSetMB = status.WorkingSetMB,
                    activeAllocations = status.ActiveAllocations
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Health check failed");
            return StatusCode(503, new
            {
                status = "Unhealthy",
                timestamp = DateTime.UtcNow,
                error = "Unable to retrieve memory status"
            });
        }
    }

    [HttpGet("ready")]
    public IActionResult Ready()
    {
        // Readiness check - more comprehensive than liveness
        try
        {
            var status = _memoryService.GetMemoryStatus();
            
            // Check if memory usage is reasonable (not completely exhausted)
            if (status.WorkingSetMB > 8192) // 8GB threshold for readiness
            {
                return StatusCode(503, new
                {
                    status = "NotReady",
                    reason = "High memory usage",
                    workingSetMB = status.WorkingSetMB
                });
            }

            return Ok(new
            {
                status = "Ready",
                timestamp = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Readiness check failed");
            return StatusCode(503, new
            {
                status = "NotReady",
                timestamp = DateTime.UtcNow,
                error = ex.Message
            });
        }
    }

    [HttpGet("live")]
    public IActionResult Live()
    {
        // Simple liveness check - just confirm the application is responding
        return Ok(new
        {
            status = "Alive",
            timestamp = DateTime.UtcNow
        });
    }
}