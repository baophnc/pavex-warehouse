# Pavex Bưu cục (pavex-warehouse)

Ứng dụng di động (Flutter) cho nhân sự hiện trường của Pavex:

| Chức danh | Tab | Việc chính |
|---|---|---|
| Bưu tá (`COURIER`) | Hôm nay · Việc · Quét · Tiền · Báo cáo | Lấy hàng, xuất giao, giao hàng (ảnh/chữ ký), thu tiền, nộp tiền về bưu cục |
| Nhân viên bưu cục (`WAREHOUSE_OPERATOR`) | Hôm nay · Việc · Quét · Tiền · Báo cáo | Nhập kho, kiểm kho, theo dõi tiền tại bưu cục |
| Trưởng bưu cục (`HUB_MANAGER`) | như nhân viên bưu cục | Thêm báo cáo của cả bưu cục, gửi duyệt lại tiền bị trả |
| Tài xế trung chuyển (`LINE_HAUL_DRIVER`) | Hôm nay · Việc · Quét · Báo cáo | Quét lên xe |

## Chạy thử

```bash
flutter pub get
flutter run
```

Ở màn đăng nhập, bấm **Máy chủ** để trỏ tới API gateway:

- iOS simulator / macOS: `http://localhost:8080`
- Android emulator: `http://10.0.2.2:8080`
- Điện thoại thật cùng Wi‑Fi: `http://<IP máy chạy backend>:8080`

## Luồng quét mã

Người dùng chọn việc đang làm (Lấy hàng, Nhập kho, Lên xe, Xuất giao, Kiểm kho, Tra cứu) rồi quét mã QR trên nhãn kiện
(hoặc mã vận đơn). App gửi `POST /api/v1/workforce/scans` với `action`; máy chủ tự xác định trạng thái kế tiếp, bưu cục,
việc được giao và chặng xe. Quét mã vận đơn sẽ áp dụng cho mọi kiện của đơn.

## API dùng

- `POST /api/v1/auth/login`, `/refresh`, `/logout`, `GET /api/v1/auth/me`
- `GET /api/v1/operations/me/hub-scope`, `GET|PUT /api/v1/operations/availability`, ca làm `/api/v1/operations/shifts/mine`
- Việc: `GET /api/v1/workforce/tasks`, `POST /api/v1/operations/assignments/{id}/accept|start|reject`
- Quét và tra cứu: `POST /api/v1/workforce/scans`, `GET /api/v1/workforce/lookup/{code}`
- Giao hàng: `GET /api/v1/deliveries/mine`, `POST /api/v1/workforce/evidence`, `POST /api/v1/deliveries/attempts`
- Tiền: `/api/v1/billing/cash/collections/mine`, `/remittances`, `/hubs/{hubId}/collections`
- Báo cáo: `GET /api/v1/workforce/reports/summary`, `GET /api/v1/workforce/reports/items`

## Kiểm tra

```bash
flutter analyze
flutter test
```
