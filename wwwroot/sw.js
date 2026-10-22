const CACHE_NAME = 'ambulanceway-v31'; // tăng số khi đổi CSS/JS để trình duyệt bỏ bản cache cũ

// Chỉ lưu sẵn tài nguyên tĩnh. Không lưu trang HTML hay dữ liệu cần đăng nhập:
// bản cache cũ của chúng có thể thuộc về người dùng khác trên cùng trình duyệt.
const urlsToCache = [
    '/css/site.css',
    '/css/aw-admin.css',
    '/css/aw-public.css',
    '/js/site.js',
    '/js/aw-public.js',
    'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css',
    'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js',
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css',
    'https://cdnjs.cloudflare.com/ajax/libs/microsoft-signalr/6.0.1/signalr.min.js',
    'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',
    'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
];

// Máy chủ CDN chứa thư viện/phông chữ: nội dung theo phiên bản cố định nên cache được
const STATIC_HOSTS = ['cdn.jsdelivr.net', 'cdnjs.cloudflare.com', 'unpkg.com', 'fonts.googleapis.com', 'fonts.gstatic.com'];
const STATIC_PATHS = ['/css/', '/js/', '/lib/', '/images/', '/favicon'];

// 1. Cài đặt: lưu tài nguyên tĩnh. Một tệp lỗi không được làm hỏng cả lần cài đặt.
self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => Promise.allSettled(urlsToCache.map(url => cache.add(url))))
            .then(() => self.skipWaiting())
    );
});

// 2. Kích hoạt: xóa cache cũ (kể cả bản cũ lỡ lưu phản hồi có token đăng nhập)
self.addEventListener('activate', event => {
    event.waitUntil(
        Promise.all([
            self.clients.claim(),
            caches.keys().then(names => Promise.all(names.filter(n => n !== CACHE_NAME).map(n => caches.delete(n))))
        ])
    );
});

function isStatic(request) {
    if (request.method !== 'GET') return false;
    const url = new URL(request.url);
    if (url.origin === self.location.origin) return STATIC_PATHS.some(p => url.pathname.startsWith(p));
    return STATIC_HOSTS.includes(url.hostname);
}

// 3. Xử lý yêu cầu
self.addEventListener('fetch', event => {
    const request = event.request;

    // A. Trang HTML: luôn lấy từ máy chủ; mất mạng thì báo rõ thay vì hiện trang cũ
    if (request.mode === 'navigate') {
        event.respondWith(fetch(request).catch(() => offlinePage()));
        return;
    }

    // B. Tài nguyên tĩnh: dùng bản cache ngay, cập nhật ngầm (stale-while-revalidate)
    if (isStatic(request)) {
        event.respondWith(
            caches.match(request).then(cached => {
                const network = fetch(request).then(response => {
                    if (response.ok) {
                        const copy = response.clone();
                        caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
                    }
                    return response;
                });
                return cached || network;
            })
        );
        return;
    }

    // C. Còn lại (API, token, SignalR, bản đồ...): đi thẳng tới mạng, không cache.
    // Trước đây yêu cầu ghi bị "xếp hàng offline" và trả 202 dù chưa gửi được (mất cả nội dung),
    // nên người dùng tưởng SOS đã gửi. Giờ để lỗi mạng hiện ra cho trang tự báo.
});

function offlinePage() {
    const html = '<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
        '<title>Mất kết nối - AmbulanceWay</title></head>' +
        '<body style="font-family:system-ui,sans-serif;display:grid;place-items:center;min-height:100vh;margin:0;background:#f1f5f9;color:#0f172a">' +
        '<div style="text-align:center;padding:24px;max-width:420px">' +
        '<h1 style="font-size:1.4rem">Không kết nối được máy chủ</h1>' +
        '<p style="color:#64748b">Kiểm tra mạng rồi tải lại trang. Trường hợp khẩn cấp, hãy gọi ngay tổng đài 115.</p>' +
        '<p><a href="tel:115" style="display:inline-block;background:#e53935;color:#fff;padding:12px 22px;border-radius:12px;text-decoration:none;font-weight:700">Gọi 115</a> ' +
        '<button onclick="location.reload()" style="padding:12px 22px;border-radius:12px;border:1px solid #cbd5e1;background:#fff;font-weight:600">Tải lại</button></p>' +
        '</div></body></html>';
    return new Response(html, { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}
