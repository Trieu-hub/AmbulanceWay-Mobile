using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Mvc;

namespace AmbulanceWay.Controllers.Api
{
    /// <summary>
    /// Endpoint không cần đăng nhập để app mobile kiểm tra địa chỉ máy chủ đã nhập đúng chưa.
    /// </summary>
    [ApiController]
    [Route("api/mobile")]
    public class MobileInfoController : ControllerBase
    {
        private readonly IWebHostEnvironment _env;
        private readonly IServer _server;

        public MobileInfoController(IWebHostEnvironment env, IServer server)
        {
            _env = env;
            _server = server;
        }

        // GET /api/mobile/ping
        [HttpGet("ping")]
        public IActionResult Ping()
        {
            var addresses = _server.Features.Get<IServerAddressesFeature>()?.Addresses ?? new List<string>();
            var ports = LanHttpPorts(addresses);
            // phoneReachable = false: backend chỉ nghe trên localhost (profile "http"), điện thoại không vào được.
            var phoneReachable = ports.Count > 0;
            // Khi chạy thử: gửi kèm địa chỉ mà điện thoại cùng Wi-Fi nên nhập, để app trên máy tính
            // (đang dùng localhost) hiện ra cho người dùng chép sang điện thoại.
            var lanUrls = _env.IsDevelopment()
                ? PhoneUrls(ports)
                : new List<string>();
            return Ok(new { ok = true, app = "AmbulanceWay", serverTimeUtc = DateTime.UtcNow, phoneReachable, lanUrls });
        }

        /// <summary>
        /// Các cổng HTTP mà máy khác trong mạng LAN gọi tới được (backend nghe trên 0.0.0.0 / [::] / IP LAN).
        /// Rỗng nghĩa là chỉ nghe trên localhost.
        /// </summary>
        public static List<int> LanHttpPorts(IEnumerable<string> listeningUrls) => listeningUrls
            .Select(url => new Uri(url.Replace("://*", "://0.0.0.0").Replace("://+", "://0.0.0.0")))
            .Where(uri => !uri.IsLoopback && uri.Scheme == Uri.UriSchemeHttp)
            .Select(uri => uri.Port)
            .Distinct()
            .ToList();

        /// <summary>Địa chỉ điện thoại cùng Wi-Fi nhập vào app, ví dụ http://192.168.1.10:5199.</summary>
        public static List<string> PhoneUrls(IReadOnlyCollection<int> lanPorts) => LanIPv4Addresses()
            .SelectMany(ip => lanPorts.Select(port => $"http://{ip}:{port}"))
            .ToList();

        /// <summary>
        /// IPv4 của máy này trên mạng LAN/Wi-Fi (bỏ loopback, 169.254.x.x và card mạng ảo không có gateway
        /// như Hyper-V, WSL, VirtualBox).
        /// </summary>
        public static List<string> LanIPv4Addresses()
        {
            var withGateway = new List<string>();
            var others = new List<string>();
            try
            {
                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus != OperationalStatus.Up
                        || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback
                        || nic.NetworkInterfaceType == NetworkInterfaceType.Tunnel)
                        continue;

                    var props = nic.GetIPProperties();
                    var hasGateway = props.GatewayAddresses.Any(g =>
                        g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any));

                    foreach (var unicast in props.UnicastAddresses)
                    {
                        var ip = unicast.Address;
                        if (ip.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(ip)) continue;
                        if (ip.GetAddressBytes()[0] == 169 && ip.GetAddressBytes()[1] == 254) continue;
                        (hasGateway ? withGateway : others).Add(ip.ToString());
                    }
                }
            }
            catch (NetworkInformationException)
            {
                // Không đọc được danh sách card mạng: bỏ qua, chỉ là thông tin gợi ý.
            }
            return withGateway.Count > 0 ? withGateway : others;
        }
    }
}
