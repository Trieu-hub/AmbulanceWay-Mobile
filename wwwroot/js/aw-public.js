// Tiện ích dùng chung cho các trang ngoài khu quản trị (bản đồ tài xế, đăng nhập và SOS của người dân).
// Logic giống phần lõi của app Flutter (mobile/lib/core, services/routing_service.dart).
window.AW = (function () {
    'use strict';

    const HCMC = { lat: 10.7769, lng: 106.7009 };
    const OSRM = 'https://router.project-osrm.org';

    // ----- Chuỗi, số, thời gian -----

    function esc(value) {
        return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    // SignalR của máy chủ giữ tên trường PascalCase, API JSON thì camelCase: đưa hết về camelCase.
    function camel(value) {
        if (Array.isArray(value)) return value.map(camel);
        if (value && typeof value === 'object') {
            const out = {};
            for (const [k, v] of Object.entries(value)) out[k.charAt(0).toLowerCase() + k.slice(1)] = camel(v);
            return out;
        }
        return value;
    }

    // Máy chủ trả DateTime từ SQL Server không kèm múi giờ nhưng thực chất là UTC.
    function parseServerTime(value) {
        if (!value) return null;
        if (value instanceof Date) return value;
        const s = String(value);
        const d = new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + 'Z');
        return isNaN(d) ? null : d;
    }

    function fmtKm(km) {
        if (km == null || isNaN(km)) return '--';
        return km < 1 ? Math.round(km * 1000) + ' m' : km.toFixed(km < 10 ? 1 : 0).replace('.', ',') + ' km';
    }

    function fmtMinutes(min) {
        if (min == null || isNaN(min)) return '--';
        min = Math.max(1, Math.round(min));
        if (min < 60) return min + ' phút';
        return Math.floor(min / 60) + ' giờ ' + (min % 60 ? (min % 60) + ' phút' : '');
    }

    function fmtClock(date) {
        return date ? date.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' }) : '--';
    }

    function fmtDateTime(date) {
        return date ? date.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit', year: 'numeric' }) : '--';
    }

    function timeAgo(date) {
        if (!date) return '';
        const sec = Math.max(0, (Date.now() - date.getTime()) / 1000);
        if (sec < 45) return 'vừa xong';
        if (sec < 3600) return Math.round(sec / 60) + ' phút trước';
        if (sec < 86400) return Math.round(sec / 3600) + ' giờ trước';
        return fmtDateTime(date);
    }

    function initials(name) {
        const parts = String(name || '?').trim().split(/\s+/);
        return ((parts.length > 1 ? parts[parts.length - 2][0] : '') + parts[parts.length - 1][0]).toUpperCase();
    }

    // ----- Gọi API -----

    class ApiError extends Error {
        constructor(message, status, data) {
            super(message);
            this.status = status;
            this.data = data;
        }
    }

    function defaultMessage(status) {
        if (status === 401) return 'Phiên đăng nhập đã hết, vui lòng đăng nhập lại.';
        if (status === 403) return 'Bạn không có quyền thực hiện thao tác này.';
        if (status === 404) return 'Không tìm thấy dữ liệu.';
        if (status >= 500) return 'Máy chủ đang gặp lỗi, vui lòng thử lại.';
        return 'Yêu cầu không hợp lệ.';
    }

    async function api(method, url, options) {
        const { token, body } = options || {};
        const headers = { Accept: 'application/json' };
        if (body !== undefined) headers['Content-Type'] = 'application/json';
        if (token) headers.Authorization = 'Bearer ' + token;

        let res;
        try {
            res = await fetch(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), credentials: 'same-origin' });
        } catch {
            throw new ApiError('Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.', 0, null);
        }

        const text = await res.text();
        let data = null;
        try { data = text ? JSON.parse(text) : null; } catch { data = null; }
        if (!res.ok) {
            const msg = data && (data.message || data.Message || data.title);
            throw new ApiError(msg || defaultMessage(res.status), res.status, data);
        }
        return data;
    }

    // ----- Thông báo -----

    function toast(message, type, ms) {
        type = type || 'info';
        let host = document.getElementById('aw-toasts');
        if (!host) {
            host = document.createElement('div');
            host.id = 'aw-toasts';
            host.setAttribute('role', 'status');
            host.setAttribute('aria-live', 'polite');
            document.body.appendChild(host);
        }
        const icon = { success: 'fa-circle-check', error: 'fa-circle-exclamation', warn: 'fa-triangle-exclamation', info: 'fa-circle-info' }[type] || 'fa-circle-info';
        const el = document.createElement('div');
        el.className = 'aw-toast is-' + type;
        el.innerHTML = '<i class="fa-solid ' + icon + '"></i><div>' + esc(message) + '</div>';
        host.appendChild(el);
        while (host.children.length > 4) host.firstElementChild.remove();
        setTimeout(() => {
            el.classList.add('is-leaving');
            setTimeout(() => el.remove(), 260);
        }, ms || (type === 'error' ? 6000 : 4200));
    }

    // Hộp thoại xác nhận. Trả về Promise<boolean>.
    function confirmDialog(opts) {
        return new Promise((resolve) => {
            const wrap = document.createElement('div');
            wrap.className = 'aw-modal';
            wrap.innerHTML =
                '<div class="aw-modal-card" role="dialog" aria-modal="true">' +
                '<div class="aw-modal-body">' +
                (opts.icon ? '<div class="aw-confirm-icon ' + (opts.tone || '') + '"><i class="fa-solid ' + opts.icon + '"></i></div>' : '') +
                '<h3 class="aw-modal-title">' + esc(opts.title) + '</h3>' +
                (opts.html ? '<div class="aw-modal-text">' + opts.html + '</div>' : '<p class="aw-modal-text">' + esc(opts.text || '') + '</p>') +
                '</div>' +
                '<div class="aw-modal-actions">' +
                '<button type="button" class="aw-btn aw-btn-light" data-x="0">' + esc(opts.cancelText || 'Hủy') + '</button>' +
                '<button type="button" class="aw-btn ' + (opts.okClass || 'aw-btn-primary') + '" data-x="1">' + esc(opts.okText || 'Đồng ý') + '</button>' +
                '</div></div>';
            const done = (v) => {
                // Hộp thoại có ô chọn/nhập (ví dụ lý do hủy): giữ lại giá trị trước khi gỡ khỏi trang
                const field = wrap.querySelector('select, textarea, input');
                confirmDialog.lastValue = field ? field.value : null;
                document.removeEventListener('keydown', onKey);
                wrap.remove();
                resolve(v);
            };
            const onKey = (e) => { if (e.key === 'Escape') done(false); };
            wrap.addEventListener('click', (e) => {
                if (e.target === wrap) return done(false);
                const b = e.target.closest('[data-x]');
                if (b) done(b.dataset.x === '1');
            });
            document.addEventListener('keydown', onKey);
            document.body.appendChild(wrap);
            wrap.querySelector('[data-x="1"]').focus();
        });
    }

    // ----- Địa lý, lộ trình -----

    function haversineKm(a, b) {
        const R = 6371, rad = Math.PI / 180;
        const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
        const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
        return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
    }

    // Xe cấp cứu trong nội đô: trung bình ~30 km/h
    function estimateMinutes(km) { return Math.max(1, Math.round(km / 30 * 60)); }

    function describeStep(step) {
        const m = step.maneuver || {};
        const road = step.name || '';
        const onto = road ? ' vào ' + road : '';
        switch (m.type) {
            case 'depart': return road ? 'Xuất phát trên ' + road : 'Xuất phát';
            case 'arrive': return 'Đến nơi';
            case 'roundabout': case 'rotary': return 'Vào vòng xuyến' + onto;
            case 'merge': return 'Nhập làn' + onto;
            case 'on ramp': return 'Vào đường dẫn' + onto;
            case 'off ramp': return 'Ra khỏi đường chính' + onto;
        }
        switch (m.modifier) {
            case 'left': return 'Rẽ trái' + onto;
            case 'right': return 'Rẽ phải' + onto;
            case 'slight left': return 'Chếch sang trái' + onto;
            case 'slight right': return 'Chếch sang phải' + onto;
            case 'sharp left': return 'Rẽ gắt sang trái' + onto;
            case 'sharp right': return 'Rẽ gắt sang phải' + onto;
            case 'uturn': return 'Quay đầu' + onto;
            default: return road ? 'Đi thẳng trên ' + road : 'Đi thẳng';
        }
    }

    function stepIcon(step) {
        const m = step.maneuver || {};
        if (m.type === 'arrive') return 'fa-flag-checkered';
        if (m.type === 'depart') return 'fa-location-arrow';
        if (m.type === 'roundabout' || m.type === 'rotary') return 'fa-rotate-right';
        if ((m.modifier || '').includes('left')) return 'fa-arrow-left';
        if ((m.modifier || '').includes('right')) return 'fa-arrow-right';
        if (m.modifier === 'uturn') return 'fa-arrow-rotate-left';
        return 'fa-arrow-up';
    }

    // Luôn trả về một lộ trình: OSRM lỗi thì ước lượng theo đường thẳng (hệ số quanh co 1,3).
    async function route(from, to) {
        try {
            const url = OSRM + '/route/v1/driving/' + from.lng + ',' + from.lat + ';' + to.lng + ',' + to.lat +
                '?overview=full&geometries=geojson&steps=true';
            const ctrl = new AbortController();
            const timer = setTimeout(() => ctrl.abort(), 10000);
            const res = await fetch(url, { signal: ctrl.signal });
            clearTimeout(timer);
            if (res.ok) {
                const data = await res.json();
                const r = data && data.code === 'Ok' && data.routes && data.routes[0];
                if (r && r.geometry && r.geometry.coordinates.length >= 2) {
                    const steps = [];
                    (r.legs || []).forEach((leg) => (leg.steps || []).forEach((s) => steps.push({
                        text: describeStep(s), icon: stepIcon(s), distance: s.distance
                    })));
                    return {
                        points: r.geometry.coordinates.map((c) => [c[1], c[0]]),
                        distanceKm: r.distance / 1000,
                        minutes: Math.max(1, Math.round(r.duration / 60)),
                        steps,
                        estimate: false
                    };
                }
            }
        } catch { /* mất mạng / quá thời gian: dùng ước lượng */ }
        const km = haversineKm(from, to) * 1.3;
        return {
            points: [[from.lat, from.lng], [to.lat, to.lng]],
            distanceKm: km,
            minutes: estimateMinutes(km),
            steps: [],
            estimate: true
        };
    }

    // Đoạn đường còn lại tính từ điểm gần vị trí hiện tại nhất trên tuyến.
    function remainingKm(points, pos) {
        if (!points || points.length < 2) return null;
        let best = 0, bestD = Infinity;
        for (let i = 0; i < points.length; i++) {
            const d = haversineKm(pos, { lat: points[i][0], lng: points[i][1] });
            if (d < bestD) { bestD = d; best = i; }
        }
        let km = bestD;
        for (let i = best; i < points.length - 1; i++) {
            km += haversineKm({ lat: points[i][0], lng: points[i][1] }, { lat: points[i + 1][0], lng: points[i + 1][1] });
        }
        return { km, index: best, offRouteKm: bestD };
    }

    async function reverseGeocode(lat, lng) {
        try {
            const res = await fetch('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&accept-language=vi&lat=' + lat + '&lon=' + lng);
            if (!res.ok) return null;
            const data = await res.json();
            if (!data || !data.address) return data && data.display_name || null;
            const a = data.address;
            const parts = [
                [a.house_number, a.road].filter(Boolean).join(' '),
                a.quarter || a.suburb || a.neighbourhood,
                a.city_district || a.district || a.county,
                a.city || a.town || a.state
            ].filter(Boolean);
            return parts.length ? [...new Set(parts)].join(', ') : data.display_name;
        } catch {
            return null;
        }
    }

    // ----- Bản đồ -----

    function baseMap(el, options) {
        const map = L.map(el, Object.assign({ zoomControl: false, attributionControl: true }, options || {}));
        L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19,
            attribution: '&copy; OpenStreetMap'
        }).addTo(map);
        map.attributionControl.setPrefix(false);
        return map;
    }

    function pin(icon, tone, opts) {
        opts = opts || {};
        const size = opts.small ? 28 : 38;
        return L.divIcon({
            className: 'aw-pin',
            html: '<div class="aw-pin-badge is-' + tone + (opts.small ? ' is-small' : '') + (opts.pulse ? ' aw-pin-pulse' : '') + '"><i class="fa-solid ' + icon + '"></i></div>',
            iconSize: [size, size],
            iconAnchor: [size / 2, size / 2]
        });
    }

    const icons = {
        car: () => L.divIcon({ className: 'aw-pin', html: '<div class="aw-car"><i class="fa-solid fa-truck-medical"></i></div>', iconSize: [44, 44], iconAnchor: [22, 22] }),
        patient: (pulse) => pin('fa-person-falling-burst', 'red', { pulse }),
        hospital: (small, open) => pin('fa-hospital', open === false ? 'gray' : 'green', { small }),
        me: () => pin('fa-house-medical', 'blue')
    };

    // Di chuyển ghim mượt thay vì nhảy cóc mỗi lần có tọa độ mới.
    function glide(marker, to, ms) {
        const from = marker.getLatLng();
        const target = L.latLng(to.lat, to.lng);
        if (from.distanceTo(target) > 2000 || document.hidden) { marker.setLatLng(target); return; }
        const t0 = performance.now();
        ms = ms || 900;
        if (marker._awFrame) cancelAnimationFrame(marker._awFrame);
        const step = (now) => {
            const k = Math.min(1, (now - t0) / ms);
            const e = k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
            marker.setLatLng([from.lat + (target.lat - from.lat) * e, from.lng + (target.lng - from.lng) * e]);
            if (k < 1) marker._awFrame = requestAnimationFrame(step);
        };
        marker._awFrame = requestAnimationFrame(step);
    }

    // Tiếng "bíp" báo ca mới (trình duyệt chỉ cho phát sau khi người dùng đã bấm vào trang).
    let audio = null;
    function unlockSound() {
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            if (audio.state === 'suspended') audio.resume();
        } catch { audio = null; }
    }
    function beep(times) {
        if (!audio) return;
        for (let i = 0; i < (times || 3); i++) {
            const t = audio.currentTime + i * 0.32;
            const osc = audio.createOscillator();
            const gain = audio.createGain();
            osc.type = 'square';
            osc.frequency.setValueAtTime(i % 2 ? 660 : 880, t);
            gain.gain.setValueAtTime(0.0001, t);
            gain.gain.exponentialRampToValueAtTime(0.12, t + 0.02);
            gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.24);
            osc.connect(gain).connect(audio.destination);
            osc.start(t);
            osc.stop(t + 0.26);
        }
    }

    return {
        HCMC, esc, camel, parseServerTime, fmtKm, fmtMinutes, fmtClock, fmtDateTime, timeAgo, initials,
        ApiError, api, toast, confirm: confirmDialog,
        haversineKm, estimateMinutes, route, remainingKm, reverseGeocode,
        baseMap, icons, glide, unlockSound, beep
    };
})();
