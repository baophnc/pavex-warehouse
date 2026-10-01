/// What a worker should read for a backend error code. Backend messages are English and written
/// for developers; anything not listed here falls back to a generic sentence by status.
const errorMessages = <String, String>{
  // Shifts and availability
  'invalid_check_in': 'Chưa vào ca được: chỉ vào ca từ 30 phút trước giờ bắt đầu đến khi ca kết thúc.',
  'invalid_check_out': 'Bạn chưa vào ca này nên không ra ca được.',
  'another_shift_checked_in': 'Bạn đang ở trong một ca khác. Ra ca đó trước rồi mới vào ca này.',
  'shift_cancelled': 'Ca này đã bị huỷ.',
  'member_not_eligible_for_shift': 'Bạn không còn thuộc bưu cục của ca này.',
  'shift_assignment_not_found': 'Bạn không có tên trong ca này.',
  'member_not_active': 'Hồ sơ nhân sự của bạn đang tạm khoá. Liên hệ trưởng bưu cục.',
  'identity_access_revoked': 'Tài khoản không còn quyền làm việc này. Liên hệ trưởng bưu cục.',
  'workforce_member_not_found': 'Tài khoản chưa có hồ sơ nhân sự. Liên hệ trưởng bưu cục.',
  'availability_not_found': 'Chưa có trạng thái nhận việc. Liên hệ trưởng bưu cục.',
  // Jobs
  'invalid_assignment_transition': 'Việc này đã được nhận hoặc đang làm. Kéo xuống để tải lại.',
  'assignment_changed': 'Việc vừa thay đổi. Kéo xuống để tải lại.',
  'assignment_not_found': 'Không còn thấy việc này (có thể đã giao cho người khác).',
  'assignee_not_eligible': 'Bạn không còn đủ điều kiện làm việc này (khác bưu cục hoặc khác chức danh).',
  'assignment_not_assigned': 'Việc này chưa giao cho ai.',
  'assignment_not_started': 'Bấm “Bắt đầu” việc này trước khi quét.',
  // Scans and deliveries
  'shipment_not_found': 'Không tìm thấy vận đơn hoặc kiện này.',
  'parcel_not_found': 'Không tìm thấy kiện này.',
  'scan_hub_forbidden': 'Bạn không làm ở bưu cục của kiện này.',
  'delivery_custody_mismatch': 'Kiện này không nằm trong chuyến giao của bạn.',
  'delivery_attempt_not_owned': 'Lần giao này không phải của bạn.',
  'collection_amount_required': 'Nhập số tiền đã thu của người nhận.',
  'collection_amount_mismatch': 'Số tiền thu phải đúng bằng số tiền trên nhãn.',
  'collection_not_expected': 'Đơn này không phải thu tiền.',
  // Cash
  'cash_hub_forbidden': 'Bạn không làm ở bưu cục này nên không nộp tiền vào đây được.',
  'cash_collection_not_held': 'Có khoản tiền không còn do bạn giữ. Tải lại rồi chọn lại.',
  'cash_hub_mismatch': 'Tiền phải nộp về đúng bưu cục giao hàng của đơn.',
  'cash_remittance_mismatch': 'Tổng tiền khai không khớp với các đơn đã chọn.',
  // Line-haul trips
  'fleet_consent_required': 'Bạn cần đồng ý chia sẻ vị trí trước khi chạy chuyến.',
  // Accounts
  'invalid_credentials': 'Sai email hoặc mật khẩu.',
  'account_locked': 'Tài khoản tạm khoá do nhập sai nhiều lần. Thử lại sau ít phút.',
  'validation_failed': 'Thông tin chưa hợp lệ. Kiểm tra lại các ô đã nhập.',
};
