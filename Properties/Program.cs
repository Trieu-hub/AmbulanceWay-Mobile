using AmbulanceWay.Data;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Models;
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllersWithViews();

builder.Services.AddDbContext<AmbulanceWayDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(60);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});

builder.Services.AddHttpContextAccessor();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseSession();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<AmbulanceWayDbContext>();

    var admin = context.Users.FirstOrDefault(x => x.Username == "admin");

    if (admin == null)
    {
        context.Users.Add(new User
        {
            Username = "admin",
            PasswordHash = "123",
            Role = "admin",
            Status = "ACTIVE",
            IsOnline = false,
            CreatedAt = DateTime.Now
        });

        context.SaveChanges();
    }
}
app.Run();