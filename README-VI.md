# RidgeKey Goodix 533c — bản tích hợp thử nghiệm

Đã gộp toàn bộ sửa build Fix2–Fix4 vào source. Không cần áp dụng từng bản vá.
README tiếng Anh là hướng dẫn kỹ thuật đầy đủ.

## Trạng thái

Chủ máy Dell XPS 9500 / Goodix 27c6:533c báo đã build, cài, đăng ký, verify,
giữ mẫu qua restart dịch vụ và mở khóa màn hình thành công; các ngón chưa đăng ký
đã thử bị từ chối. Chỉ thử trên một máy, chưa có thống kê độ chính xác hoặc audit.
Chưa ghi nhận riêng bài thử giữ mẫu qua reboot toàn máy.
Cảm biến thử dùng firmware 13016 và zero PSK đã được chuẩn bị từ trước.
Gói không reset/flash/cấu hình khóa cảm biến mới.

## Cài từ source trên Dell

Giải nén/clone vào ổ trong, mở Terminal tại thư mục có Source và Build.command:

```bash
xcode-select -p
bash Check-Keychain.command
bash Build.command
```

Thiếu CLT thì cài bằng `xcode-select --install`. Chờ BUILD_COMPLETE rồi chạy:

```bash
bash Install-Test.command
```

Không chạy các lệnh trên bằng sudo; script tự hỏi khi cần. Không cần chỉnh EFI.
Nếu đã cài RidgeKey gốc 1.0.0, xem docs/MIGRATION.md trước.
Mở app đăng ký ngón; giữ tay khỏi cảm biến trong lúc hiệu chuẩn ban đầu.

## Kiểm tra và bật mở khóa

```bash
bash Verify-Persistence.command
/usr/local/bin/ridgekeyctl verify -t 45
```

Thử nhiều lần ngón đúng và các ngón chưa đăng ký. Nếu ngón khác được nhận, chưa
bật mở khóa. Khi kiểm tra ổn, chạy Enable-Unlock.command, nhập mật khẩu cục bộ,
cấp Accessibility cho RidgeKey Agent và thử Control-Command-Q.
Disable-Unlock.command tắt tự nhập mật khẩu mà giữ các ngón đã lưu.
Đây là agent nhập mật khẩu sau nhận diện, không phải Apple Touch ID/FileVault/Apple Pay.
Không bật công cụ sudo/admin của upstream trong bản này.

## Đưa lên GitHub

Đưa toàn bộ nội dung thư mục repo lên một repository mới; giữ Source, patches,
UPSTREAM.json và giấy phép. Không lấy EFI, log cá nhân hoặc Keychain để upload.
Nếu cần binary cho GitHub Release, chạy Export-Release.command trên Dell đã build.
Không cần build lại chỉ để xuất archive. Luôn kèm source tương ứng khi chia sẻ binary.
