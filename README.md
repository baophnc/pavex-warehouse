# Pavex Hiện trường (pavex-warehouse)

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

Bản debug/profile: ở màn đăng nhập, bấm **Máy chủ** để trỏ tới API gateway (bản phát hành không có nút này, xem
[Bản phát hành](#bản-phát-hành)):

- iOS simulator / macOS: `http://localhost:8080`
- Android emulator: `http://10.0.2.2:8080`
- Điện thoại thật cùng Wi‑Fi: `http://<IP máy chạy backend>:8080` (tường lửa macOS phải cho Java nhận kết nối)

### Điện thoại Android thật qua cáp USB (dễ nhất)

Bật *Tuỳ chọn nhà phát triển → Gỡ lỗi USB*, cắm cáp, rồi chuyển cổng 8080 của điện thoại về máy:

```bash
~/Library/Android/sdk/platform-tools/adb reverse tcp:8080 tcp:8080
flutter run --dart-define=PAVEX_API_BASE_URL=http://localhost:8080
```

`--dart-define` đặt sẵn địa chỉ máy chủ cho bản build; địa chỉ đã lưu trong app (nút **Máy chủ**) vẫn được ưu
tiên. Rút cáp ra cắm lại thì chạy lại lệnh `adb reverse`.

### Thử nhanh mọi giờ

Đặt `OPERATIONS_SHIFT_FULL_DAY=true` trong `.env` của backend: ai cũng có ca 00:00–24:00 mỗi ngày nên vào ca và
nhận việc lúc nào cũng được. Tài khoản test nằm trong `scripts/seed-mini/README.md` của backend.

## Docker (bản web + APK Android)

`Dockerfile` ở gốc repo build trong một image: bản web của app, tệp APK Android và trang tải về. Image chạy nginx
không quyền root, cổng **8080** trong container:

| Đường dẫn | Nội dung |
|---|---|
| `/` | Bản web (`flutter build web`) để dùng thử trên trình duyệt |
| `/download/` | Trang tải APK: liên kết, mã QR, phiên bản, cách cài (cho phép cài từ nguồn không xác định) |
| `/download/pavex-field.apk` | Tệp APK |
| `/healthz` | `200 ok` cho health check |

```bash
docker build -t pavex/field-app .
docker run --rm -p 8090:8080 pavex/field-app
```

Mở `http://localhost:8090` (bản web), `http://<IP LAN của máy>:8090/download/` trên điện thoại để quét mã và cài
APK. Thường thì `docker compose up` trong repo backend build và chạy image này cùng cả hệ thống.

Tham số build (`--build-arg`):

| Tham số | Mặc định | Ý nghĩa |
|---|---|---|
| `PAVEX_API_BASE_URL` | `http://localhost:8080` | API gateway mà bản web (và APK) gọi; staging: `https://api.<domain>` |
| `APK_API_BASE_URL` | = `PAVEX_API_BASE_URL` | Địa chỉ gắn vào APK nếu điện thoại vào gateway bằng địa chỉ khác trình duyệt, ví dụ `http://192.168.1.10:8080` |
| `APK_MODE` | `debug` | `debug`: cho phép HTTP tới gateway trong LAN/localhost, đổi được máy chủ ở màn đăng nhập. `release`: bản phát hành, cần khoá ký (dưới đây) và địa chỉ `https://` |
| `ANDROID_SIGNING_ALIAS` | `upload` | Alias của khoá trong kho khoá (chỉ cho `release`) |

- Bản web là bản release nhưng được dùng `http://` (trình duyệt tự chặn gọi HTTP từ trang HTTPS). Gateway phải cho
  phép origin của trang web qua CORS: `GATEWAY_ALLOWED_ORIGIN` của backend nhận nhiều origin cách nhau bằng dấu phẩy,
  ví dụ `http://localhost:3000,http://localhost:8090`.
- Camera (quét mã), vị trí và lưu phiên đăng nhập trên trình duyệt chỉ chạy khi trang mở qua `https://` hoặc
  `localhost`; mở bằng `http://<IP>` thì app vẫn chạy, nhập mã bằng tay và tải lại trang phải đăng nhập lại. Vị trí
  chuyến xe chỉ gửi khi tab đang mở: chạy chuyến thật phải dùng app trên điện thoại.
- `APK_MODE=release` lấy khoá ký từ **build secret**, không bao giờ từ build arg hay layer của image. Thiếu khoá
  (hoặc địa chỉ không phải `https://`) thì image vẫn build, chỉ không có APK và trang `/download/` ghi rõ lý do:

  ```bash
  printf '%s' '<mật khẩu kho khoá>' > /tmp/pavex-store-pw
  docker build -t pavex/field-app \
    --build-arg APK_MODE=release --build-arg PAVEX_API_BASE_URL=https://api.pavex.vn \
    --secret id=android_keystore,src=$HOME/keys/pavex-field-upload.jks \
    --secret id=android_keystore_password,src=/tmp/pavex-store-pw .
  ```

  Mật khẩu khoá khác mật khẩu kho khoá thì thêm `--secret id=android_key_password,src=…`.
- Image build ở `linux/amd64` (aapt2 của Android và Flutter SDK cho Linux chỉ có bản x86_64). Trên Mac Apple
  Silicon bước build chạy giả lập nên chậm (lần đầu vài chục phút); bật *Use Rosetta for x86_64/amd64 emulation* trong
  Docker Desktop để nhanh hơn. Image chạy (nginx) là bản gốc của máy. Pub và Gradle được giữ trong cache của BuildKit.
- APK debug được ký bằng khoá debug lưu trong cache BuildKit của máy build; APK build trên máy khác (hoặc sau khi xoá
  cache) có khoá khác, phải gỡ bản cũ trên điện thoại trước khi cài.
- iOS không build được trong Docker: dùng Xcode như mục [Bản phát hành](#bản-phát-hành).

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

## Bản phát hành

Mã ứng dụng hiện là `vn.pavex.field` (Android `applicationId`, iOS/macOS bundle id; test iOS là
`vn.pavex.field.RunnerTests`), tên hiển thị **Pavex Hiện trường**. Đây là mã tạm cho tới khi chốt mã chính thức: đổi
được bất cứ lúc nào trước lần đầu đưa lên Google Play / App Store, sau đó đổi mã là thành một ứng dụng khác.

### Máy chủ trong bản phát hành

- Bản phát hành **chỉ** dùng địa chỉ gắn lúc build: `--dart-define=PAVEX_API_BASE_URL=https://…`. Không có nút
  **Máy chủ**, địa chỉ đã lưu từ bản debug bị bỏ qua.
- Địa chỉ phải bắt đầu bằng `https://` (không chứa tài khoản, `?` hay `#`). Thiếu hoặc sai thì app mở ra màn
  "Không thể kết nối máy chủ" thay vì màn đăng nhập.
- Địa chỉ là URL công khai của API gateway (cổng 8080 của backend đặt sau HTTPS, ví dụ `https://api.pavex.vn`), do
  người vận hành backend cung cấp; xem mục "Triển khai thật" trong `docs/PAVEX-TAI-LIEU-TONG-HOP.md` của backend.
- Mạng: Android bản release có `usesCleartextTraffic="false"` (bản debug/profile bật lại HTTP qua
  `android/app/src/debug|profile/AndroidManifest.xml`); iOS chỉ giữ `NSAllowsLocalNetworking` (localhost và mạng LAN
  cho lúc phát triển). Các thiết lập này áp cho mạng của hệ điều hành; kết nối API của app (gói `http`, `dart:io`)
  không đi qua chúng, nên quy tắc `https://` ở trên mới là chốt chặn chính.

### Android: tạo khoá ký (làm một lần)

Bản release **không** ký bằng khoá debug. Thiếu `android/key.properties` thì `flutter build` bản release dừng với
thông báo "Release build needs a signing key"; bản debug/profile không bị ảnh hưởng.

```bash
keytool -genkeypair -v -keystore ~/keys/pavex-field-upload.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Sao chép `android/key.properties.example` thành `android/key.properties` rồi điền:

```properties
storeFile=/Users/<bạn>/keys/pavex-field-upload.jks
storePassword=<mật khẩu kho khoá>
keyAlias=upload
keyPassword=<mật khẩu khoá>
```

`storeFile` là đường dẫn tuyệt đối hoặc tính từ thư mục `android/`. `key.properties`, `*.jks`, `*.keystore` đã nằm
trong `.gitignore`: **không** commit chúng. Cất kho khoá và mật khẩu ở nơi an toàn (trình quản lý mật khẩu của công
ty); mất khoá upload thì phải nhờ Google Play đặt lại. Nên bật *Play App Signing* khi tạo ứng dụng trên Play Console.

### Android: build

Tăng `version` trong `pubspec.yaml` (ví dụ `1.0.1+2`: số sau `+` là `versionCode`, phải tăng mỗi lần nộp), rồi:

```bash
flutter build appbundle --release --dart-define=PAVEX_API_BASE_URL=https://api.pavex.vn
```

Tệp nộp Google Play: `build/app/outputs/bundle/release/app-release.aab`. Cần APK để cài thẳng lên máy thì dùng
`flutter build apk --release --dart-define=…` (ra `build/app/outputs/flutter-apk/app-release.apk`).

### iOS: ký và build

Việc ký để Xcode lo, không có gì về ký trong repo:

1. Mở `ios/Runner.xcworkspace`, chọn target **Runner** → *Signing & Capabilities* → bật *Automatically manage
   signing*, chọn *Team* của tài khoản Apple Developer công ty. Bundle id `vn.pavex.field` phải được đăng ký trên
   App Store Connect (Xcode tự tạo khi ký tự động).
2. Build:

   ```bash
   flutter build ipa --release --dart-define=PAVEX_API_BASE_URL=https://api.pavex.vn
   ```

3. Tải `build/ios/ipa/*.ipa` lên App Store Connect bằng ứng dụng Transporter (hoặc mở
   `build/ios/archive/Runner.xcarchive` trong Xcode → *Distribute App*), rồi phát qua TestFlight.

App dùng vị trí nền (chuyến trung chuyển), camera và thư viện ảnh; lời giải thích quyền nằm trong
`ios/Runner/Info.plist`, khi nộp App Store cần khai báo đúng mục đích này.
