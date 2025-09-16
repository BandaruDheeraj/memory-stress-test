using MemoryStressTester.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Add health checks
builder.Services.AddHealthChecks();

// Add our memory management service
builder.Services.AddSingleton<IMemoryStressService, MemoryStressService>();

// Configure memory limits
builder.Services.Configure<MemorySettings>(builder.Configuration.GetSection("MemorySettings"));

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Serve static files (our frontend)
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

// Map health check endpoints
app.MapHealthChecks("/health");

// Fallback to index.html for SPA routing
app.MapFallbackToFile("index.html");

app.Run();
