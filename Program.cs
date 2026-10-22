using AmbulanceWay.Data;
using AmbulanceWay.Models;
using AmbulanceWay.Hubs;
using AmbulanceWay.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

// 1) Controllers + JSON settings
builder.Services.AddControllersWithViews()
    .AddJsonOptions(options =>
    {
        // Giữ nguyên property naming (PascalCase) như code hiện tại
        options.JsonSerializerOptions.PropertyNamingPolicy = null;
    });

// 2) Database
builder.Services.AddDbContext<AmbulanceWayDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        sqlOptions =>
        {
            sqlOptions.EnableRetryOnFailure(5, TimeSpan.FromSeconds(10), null);
        }));

// 3) JWT Authentication (dành cho mobile/tài xế)
builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = builder.Configuration["Jwt:Issuer"],
        ValidAudience = builder.Configuration["Jwt:Audience"],
        IssuerSigningKey = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Key"] ?? "Default_Secret_Key_At_Least_32_Chars_Long"))
    };
});

// 4) Session (dành cho web)
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});

builder.Services.AddHttpContextAccessor();
builder.Services.AddSignalR()
    .AddJsonProtocol(options =>
    {
        // Giữ nguyên tên trường (PascalCase) như ở controller phía trên.
        // Mặc định SignalR đổi sang camelCase, khiến các trang web đọc data.CaseId, data.Lat... luôn nhận undefined.
        options.PayloadSerializerOptions.PropertyNamingPolicy = null;
    });

// 5) CORS cho app Flutter chạy trên trình duyệt (flutter run -d chrome) - chỉ bật ở Development.
//    App Android/iOS/Windows không cần CORS. App dùng JWT trong header nên không cho gửi cookie.
const string MobileDevCors = "MobileDevCors";
builder.Services.AddCors(options =>
{
    options.AddPolicy(MobileDevCors, policy => policy
        .AllowAnyOrigin()
        .AllowAnyHeader()
        .AllowAnyMethod());
});

var app = builder.Build();

// --- Middleware order (quan trọng) ---
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseStaticFiles();
app.UseRouting();

if (app.Environment.IsDevelopment())
{
    app.UseCors(MobileDevCors);
}

app.UseSession();
app.UseAuthentication();
app.UseAuthorization();

// 6) Map SignalR Hub
app.MapHub<AmbulanceHub>("/ambulanceHub");

// 7) Default route
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Account}/{action=Login}/{id?}");

// 8) Seed admin (default)
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<AmbulanceWayDbContext>();

    context.Database.EnsureCreated();

    var admin = context.Users.FirstOrDefault(x => x.Username == "admin");
    if (admin == null)
    {
        context.Users.Add(new User
        {
            Username = "admin",
Password = BCrypt.Net.BCrypt.HashPassword("123"), // admin password: 123
            Role = "ADMIN",
            Status = "ACTIVE",
            IsOnline = false,
            CreatedAt = DateTime.Now
        });
        context.SaveChanges();
    }
}

app.Run();
