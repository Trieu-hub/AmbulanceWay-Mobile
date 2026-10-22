using AmbulanceWay.Hubs;
using Microsoft.AspNetCore.SignalR;
using System.Collections.Concurrent;
using AmbulanceWay.Constants; // Import AppConstants

namespace AmbulanceWay.Services
{
    public class EmergencyEscalationService : BackgroundService
    {
        private readonly IHubContext<AmbulanceHub> _hubContext;
        private readonly ILogger<EmergencyEscalationService> _logger;

        public EmergencyEscalationService(IHubContext<AmbulanceHub> hubContext, ILogger<EmergencyEscalationService> logger)
        {
            _hubContext = hubContext;
            _logger = logger;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var now = DateTime.UtcNow;
                foreach (var item in AmbulanceHub.PendingCases)
                {
                    var waitTime = (now - item.Value).TotalMinutes;
                    
                    // Cảnh báo đỏ nếu quá 3 phút (Phần 3 - Nghiệp vụ Điều phối)
                    if (waitTime >= 3)
                    { // TODO: Nên dùng hằng số cho "Admins"
                        await _hubContext.Clients.Group("Admins").SendAsync("EscalationAlert", new {
                            CaseId = item.Key,
                            WaitTime = Math.Round(waitTime, 1),
                            Message = $"CẢNH BÁO: Ca #{item.Key} chưa có người nhận sau {Math.Round(waitTime, 1)} phút!"
                        });
                    }
                }
                // Quét mỗi 15 giây để đảm bảo realtime nhưng không tốn tài nguyên
                await Task.Delay(15000, stoppingToken);
            }
        }
    }
}