import 'package:intl/intl.dart';

final _money = NumberFormat.decimalPattern('vi_VN');
final _time = DateFormat('HH:mm');
final _dayTime = DateFormat('HH:mm dd/MM');
final _day = DateFormat('dd/MM/yyyy');

String money(int value) => '${_money.format(value)} ₫';

String timeOf(DateTime? value) => value == null ? '—' : _time.format(value);

String dayTime(DateTime? value) => value == null ? '—' : _dayTime.format(value);

String day(DateTime value) => _day.format(value);

String isoDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

/// An inclusive range of calendar days.
class DateRange {
  const DateRange(this.from, this.to, this.label);

  final DateTime from;
  final DateTime to;
  final String label;

  static DateRange today([DateTime? now]) {
    final date = _dateOnly(now ?? DateTime.now());
    return DateRange(date, date, 'Hôm nay');
  }

  static DateRange lastDays(int days, [DateTime? now]) {
    final to = _dateOnly(now ?? DateTime.now());
    return DateRange(to.subtract(Duration(days: days - 1)), to, '$days ngày');
  }

  static DateRange thisMonth([DateTime? now]) {
    final today = _dateOnly(now ?? DateTime.now());
    return DateRange(DateTime(today.year, today.month), today, 'Tháng này');
  }

  bool contains(DateTime? value) {
    if (value == null) return false;
    final date = _dateOnly(value);
    return !date.isBefore(from) && !date.isAfter(to);
  }

  static DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
}

const parcelStatusLabels = {
  'AWAITING_PICKUP': 'Chờ lấy hàng',
  'PICKED_UP': 'Đã lấy hàng',
  'AT_ORIGIN_HUB': 'Tại bưu cục gửi',
  'IN_TRANSIT': 'Đang trung chuyển',
  'AT_TRANSIT_HUB': 'Tại kho trung chuyển',
  'AT_DESTINATION_HUB': 'Tại bưu cục giao',
  'OUT_FOR_DELIVERY': 'Đang giao',
  'DELIVERY_FAILED': 'Giao thất bại',
  'PARTIALLY_DELIVERED': 'Giao một phần',
  'DELIVERED': 'Đã giao',
  'RETURNING': 'Đang hoàn',
  'RETURNED': 'Đã hoàn',
  'CANCELLED': 'Đã hủy',
};

String statusLabel(String status) => parcelStatusLabels[status] ?? status;

const taskTypeLabels = {
  'PICKUP': 'Lấy hàng',
  'ORIGIN_HUB_HANDLING': 'Nhập kho gửi',
  'LINE_HAUL': 'Chuyến trung chuyển',
  'TRANSIT_HUB_HANDLING': 'Xử lý tại kho trung chuyển',
  'DESTINATION_HUB_HANDLING': 'Nhập kho giao',
  'LAST_MILE_DELIVERY': 'Giao hàng',
};

String taskTypeLabel(String type) => taskTypeLabels[type] ?? type;

const taskStatusLabels = {
  'ASSIGNED': 'Mới giao',
  'ACCEPTED': 'Đã nhận',
  'IN_PROGRESS': 'Đang làm',
  'COMPLETED': 'Xong',
  'CANCELLED': 'Đã hủy',
};

String taskStatusLabel(String status) => taskStatusLabels[status] ?? status;

/// Failure reasons the courier can pick, in the order they happen most.
const deliveryFailureReasons = {
  'RECIPIENT_UNAVAILABLE': 'Người nhận vắng mặt',
  'UNABLE_TO_CONTACT': 'Không liên lạc được',
  'RECIPIENT_REFUSED': 'Người nhận từ chối nhận',
  'INVALID_ADDRESS': 'Sai địa chỉ',
  'PAYMENT_NOT_COLLECTED': 'Người nhận chưa đủ tiền',
  'PARCEL_DAMAGED': 'Hàng bị hư hỏng',
  'UNSAFE_LOCATION': 'Địa điểm không an toàn',
  'OTHER': 'Lý do khác',
};

const cashStatusLabels = {
  'HELD': 'Đang giữ',
  'SUBMITTED': 'Đã nộp, chờ duyệt',
  'APPROVED': 'Đã duyệt',
  'REJECTED': 'Bị trả lại',
};

String cashStatusLabel(String status) => cashStatusLabels[status] ?? status;

const scanActionLabels = {
  'PICK_UP': 'Lấy hàng',
  'RECEIVE': 'Nhập kho',
  'DEPART': 'Lên xe',
  'OUT_FOR_DELIVERY': 'Xuất giao',
  'CHECK': 'Kiểm kho',
  'LOOKUP': 'Tra cứu',
};

String scanActionLabel(String action) => scanActionLabels[action] ?? action;
