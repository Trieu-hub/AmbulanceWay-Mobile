using AmbulanceWay.Constants;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace AmbulanceWay.Controllers
{
    /// <summary>
    /// Cho phép gọi API khi có JWT hợp lệ (app mobile) HOẶC khi đang đăng nhập web với quyền Admin (Session).
    /// Dùng cho các API mà cả app lẫn trang quản trị web cùng gọi, ví dụ /api/Hospitals, /api/TripHistory:
    /// trước đây chúng chỉ nhận JWT nên trang web Admin luôn báo "Không thể tải dữ liệu".
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
    public class JwtOrAdminSessionAttribute : Attribute, IAuthorizationFilter
    {
        public void OnAuthorization(AuthorizationFilterContext context)
        {
            var http = context.HttpContext;

            // JwtBearer là scheme xác thực mặc định nên token hợp lệ đã được gắn vào User trước bước này.
            if (http.User.Identity?.IsAuthenticated == true) return;

            if (http.Session.GetInt32(AppConstants.SessionRole) == AppConstants.RoleValueAdmin) return;

            context.Result = new UnauthorizedObjectResult(new { message = "Vui lòng đăng nhập" });
        }
    }
}
