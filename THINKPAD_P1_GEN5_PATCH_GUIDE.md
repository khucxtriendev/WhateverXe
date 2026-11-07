# Hướng Dẫn So Sánh Mã Nguồn & Bản Vá WhateverXe Cho Lenovo ThinkPad P1 Gen 5

Tài liệu này lưu trữ toàn bộ phân tích kỹ thuật, so sánh chi tiết giữa mã nguồn WhateverXe gốc và bản vá thực tế đang hoạt động ổn định trên **Lenovo ThinkPad P1 Gen 5**, đồng thời hướng dẫn quy trình cập nhật tự động khi tác giả ra phiên bản mới.

---

## 1. Thông Tin Phần Cứng Mục Tiêu (Target Specification)

* **Thiết bị:** Lenovo ThinkPad P1 Gen 5 (Model Type: `21DDS88B00`)
* **Vi xử lý:** Intel Core i7-12800H (Alder Lake-H, kiến trúc lai 6 P-Cores + 8 E-Cores, Display 13)
* **Card đồ hoạ tích hợp (iGPU):** Intel Iris Xe Graphics (`8086:46A6`, 96 Execution Units)
* **Card đồ hoạ rời (dGPU):** NVIDIA RTX A1000 Laptop (`10DE:25B9`)
* **Màn hình trong (Internal eDP Panel):** BOE `NE160QDM-NY1` / `LEN41B0` (16 inch, tỉ lệ 16:10, độ phân giải 2560 x 1600, khởi tạo UEFI GOP 6-bpc)
* **Hệ điều hành:** macOS Sequoia 15.8.2 (Build `24H232`) / macOS Tahoe

---

## 2. Phả Hệ & So Sánh Kiến Trúc Mã Nguồn

```
[MÃ NGUỒN GỐC THƯỢNG NGUỒN]
b00t0x/WhateverXe v0.7.0 (Commit d0b7fb62)
         │
         ▼ (Bổ sung 52 commit chuyên biệt cho Laptop Gen 12/13)
[NHÁNH LAPTOP EDPI]
Thatisjigen/WhateverXe (Branch acer/current - Commit db86632)
         │
         ▼ (Áp dụng bản vá ThinkPad P1 Gen 5 & Màn hình 2.5K BOE)
[BẢN HIỆN TẠI ĐANG CHẠY]
E:\WhateverXe build\WhateverXe
```

### So sánh tầng 1: Upstream b00t0x 0.7.0 vs Nhánh Laptop `acer/current`
* **Upstream b00t0x 0.7.0:** Thiết kế chủ yếu cho desktop và một số ít cổng xuất hình ngoài. Trên laptop Intel Core Gen 12/13 (Alder Lake/Raptor Lake), bản gốc **không thể xuất hình ra màn hình trong eDP** (bị mất tín hiệu màn hình ngay từ đầu).
* **Nhánh `acer/current` của Thatisjigen:** Bổ sung 52 commit quan trọng:
  1. Hỗ trợ điều khiển màn hình eDP Display 13 cho vi xử lý di động Gen 12/13.
  2. Bổ sung tính năng khôi phục khi GPU bị treo (`-wex-reset-recover`).
  3. Quản lý chu trình Sleep / Wake và cấp lại xung nhịp màn hình sau khi thức dậy.
  4. Hỗ trợ HiDPI DBUF (`-wex-hidpi-dbuf`) và bộ đệm quét hình (`-wex-scanout-coherent`).

### So sánh tầng 2: Nhánh `acer/current` vs Bản Vá Trên ThinkPad P1 Gen 5
Mặc dù nhánh `acer/current` đã chạy được trên Acer Nitro (màn hình 1080p 8-bpc), nhưng khi chạy trên **ThinkPad P1 Gen 5**, hệ thống sẽ gặp 3 lỗi nghiêm trọng dẫn đến sập boot hoặc đen màn hình:
1. **Lỗi `InvalidDPSource (0x0B)`:** Do UEFI GOP của ThinkPad xuất hình ở chế độ 6-bpc (`0x8a200106`), bị code gốc từ chối.
2. **Lỗi `ADLPFBTCUnavailable`:** Do controller Type-C/Thunderbolt 4 ngoài của ThinkPad chưa sẵn sàng lúc boot sớm làm kext abort toàn bộ Framebuffer.
3. **Lỗi ngắt nguồn màn hình ở giây cuối cùng (`tryCloseGate`):** Do hàm `display13OnlyPipeAFramebuffer` kiểm tra sai trạng thái phần cứng, tưởng có đa màn hình nên kích hoạt chuyển đổi clock kép làm sập xung nhịp Pipe A.

---

## 3. Chi Tiết Các Vị Trí Đã Sửa Đổi (Code Diff & Phân Tích)

File bản vá hoàn chỉnh: [`whateverxe_thinkpad_p1_gen5.patch`](whateverxe_thinkpad_p1_gen5.patch)

### Bản vá 1: Chấp nhận độ sâu màu 6-bpc (`bpc == 2`) từ UEFI GOP
* **Các file tác động:**
  * `WhateverXe/kern_alderlake_n.hpp` (Dòng 242 & 397)
  * `WhateverXe/kern_display13_boot.hpp` (Dòng 177)
  * `WhateverXe/kern_display13_fb_memory.hpp` (Dòng 422)

```diff
--- a/WhateverXe/kern_alderlake_n.hpp
+++ b/WhateverXe/kern_alderlake_n.hpp
@@ -239,7 +239,8 @@ inline bool dpSource(const DisplayReadout &boot,unsigned pipe,unsigned ddi,const
-    return (trans&0xFF700000U)==(0x82000000U|((ddi+1)<<27)) &&
+    const unsigned bpc=((trans>>20)&7);
+    return ((bpc==0 || bpc==2) && (trans&0xFF000000U)==(0x82000000U|((ddi+1)<<27))) &&
         !(trans&((1U<<15)|(1U<<9))) && !ctl2 &&
@@ -394,7 +395,7 @@ inline LinearStatus linearPlan(const DisplayReadout &r, LinearPlan &p,unsigned d
     p.geometry=XELPGeometry::linear(p.control,p.stride,p.size,p.position,p.offset);
     if(!p.geometry.valid || (p.surface&4095) || p.surface!=surfLive ||
-       ((trans>>20)&7)!=0 || (pipeConf&0xC0000000)!=0xC0000000 ||
+       (((trans>>20)&7)!=0 && ((trans>>20)&7)!=2) || (pipeConf&0xC0000000)!=0xC0000000 ||
```

```diff
--- a/WhateverXe/kern_display13_boot.hpp
+++ b/WhateverXe/kern_display13_boot.hpp
@@ -174,7 +174,7 @@ template<class IO> Result normalize(IO &io,const AlderLakeN::DisplayReadout &boo
         ports[p]=port;used|=1U<<port;
         uint32_t stride=0,size=0,position=0,offset=0,ht=0,vt=0,conf=0;
-        if(((trans>>20)&7) || !AlderLakeN::value(boot,0x70188+bank,stride) ||
+        if((((trans>>20)&7)!=0 && ((trans>>20)&7)!=2) || !AlderLakeN::value(boot,0x70188+bank,stride) ||
```

```diff
--- a/WhateverXe/kern_display13_fb_memory.hpp
+++ b/WhateverXe/kern_display13_fb_memory.hpp
@@ -419,7 +419,7 @@ template<class IO> Readout inspect(IO &io,const void *controller,size_t controll
         const auto geometry=XELPGeometry::linear(r.control,r.stride,r.size,position,offset);
         const bool source=dsi ? !(io.read(0x60400)&(1U<<31)) && XELPGeometry::timing(geometry,dsi->htotal,dsi->vtotal) :
             (dpt&(1U<<30)) && ((trans>>27)&15)==expectedDDI+1 &&
-            (dp ? ((trans>>24)&7)==2 : ((trans>>24)&7)<=1) && !((trans>>20)&7);
+            (dp ? ((trans>>24)&7)==2 : ((trans>>24)&7)<=1) && (!((trans>>20)&7) || ((trans>>20)&7)==2);
```

* **Ý nghĩa:**
  Lenovo ThinkPad P1 Gen 5 dùng màn hình 2560x1600 BOE. Firmware GOP của máy đặt giá trị `(trans >> 20) & 7 = 2` (tương ứng 6-bpc). Mã nguồn gốc bắt buộc `(trans >> 20) & 7 == 0` (8-bpc). Nếu không có bản vá này, kext sẽ từ chối bộ đệm GOP của firmware, gây panic hoặc đứng hình verbose với mã lỗi `InvalidDPSource (0x0B)`.

---

### Bản vá 2: Bỏ qua lỗi Type-C controller khi có màn hình trong (eDP Panel)
* **File tác động:** `WhateverXe/kern_xe.cpp` (Dòng 8959)

```diff
--- a/WhateverXe/kern_xe.cpp
+++ b/WhateverXe/kern_xe.cpp
@@ -8955,7 +8955,8 @@ bool XE::wrapDisplay13FramebufferStart(IOService *that,IOService *provider) {
         if(!ready)return false;
     }
     if((board.selected()&0x78) && (!s->display13FBTCHooksReady || !s->display13TCProbeReady)) {
-        IORegistryEntry::getRegistryRoot()->setProperty("ADLPFBTCUnavailable",true);return false;
+        IORegistryEntry::getRegistryRoot()->setProperty("ADLPFBTCUnavailable",true);
+        if(!s->adlnOutputWiring.panel) return false;
     }
```

* **Ý nghĩa:**
  ThinkPad P1 Gen 5 có cổng Thunderbolt 4 và Type-C phức tạp. Khi các hook Type-C chưa sẵn sàng, WhateverXe đánh dấu cờ `ADLPFBTCUnavailable` và trả về `false` (hủy bỏ khởi động Framebuffer). Thêm điều kiện `if(!s->adlnOutputWiring.panel) return false;` đảm bảo nếu máy đang có màn hình trong eDP thì **vẫn tiếp tục khởi động bình thường**, không làm tắt màn hình laptop.

---

### Bản vá 3: Đọc trực tiếp thanh ghi phần cứng chống lỗi "Đen màn hình ở giây cuối cùng"
* **File tác động:** `WhateverXe/kern_xe.cpp` (Dòng 9715)

```diff
--- a/WhateverXe/kern_xe.cpp
+++ b/WhateverXe/kern_xe.cpp
@@ -9714,7 +9715,17 @@ uint64_t XE::wrapAlderLakeNClockProbe(IOService *controller) {return adlnClockRe
 bool XE::display13OnlyPipeAFramebuffer() {
 	auto &c=display13FBPower;if(!c.lock)return false;
 	IOLockLock(c.lock);
-	const bool only=c.pipe[0].memoryFramebuffer && !c.pipe[1].memoryFramebuffer && !c.pipe[2].memoryFramebuffer;
+	bool secondaryActive=false;
+	if(c.map) {
+		Display13FBPowerIO powerIO {c.map};const auto wells=powerIO.read(Display13Power::Driver);
+		if(wells!=UINT32_MAX && (wells&3)==3 && !(wells&(1U<<16))) {
+			for(unsigned pipe=1;pipe<3;++pipe) if(wells&(1U<<(2*(5+pipe)))) {
+				const auto trans=powerIO.read(0x60400+pipe*0x1000),conf=powerIO.read(0x70008+pipe*0x1000);
+				if((trans!=UINT32_MAX && conf!=UINT32_MAX) && ((trans|conf)&(1U<<31))) secondaryActive=true;
+			}
+		}
+	}
+	const bool only=c.pipe[0].memoryFramebuffer && (!secondaryActive || (!c.pipe[1].memoryFramebuffer && !c.pipe[2].memoryFramebuffer));
 	IOLockUnlock(c.lock);return only;
 }
```

* **Ý nghĩa:**
  Đây là bản vá then chốt xử lý lỗi màn hình sáng từ đầu đến cuối nhưng **đúng giây cuối cùng khi hiện trỏ chuột thì tắt ngấm (đen màn)**.
  Mã gốc kiểm tra trạng thái bộ nhớ `pipe[1].memoryFramebuffer` qua biến mềm. Lúc WindowServer bàn giao quyền điều khiển, biến này có thể phản ánh sai khiến kext tưởng có 2 màn hình, gọi hàm đổi xung kép `adlnSetDualClock()` ➔ gọi `tryCloseGate()` làm mất xung nhịp màn hình eDP.
  Bản vá đọc trực tiếp thanh ghi phần cứng `Display13Power::Driver`, `TRANS_CONF` (`0x70008 + pipe*0x1000`) và `TRANS_CLK_SEL` (`0x60400 + pipe*0x1000`). Nếu không có tín hiệu phát trên cổng phụ, kext giữ nguyên xung nhịp Pipe A, triệt tiêu hoàn toàn lỗi đen màn hình.

---

## 4. Quy Trình Cập Nhật Khi Tác Giả Ra Phiên Bản Mới

Khi tác giả WhateverXe hoặc Thatisjigen cập nhật mã nguồn mới trên GitHub, hãy làm theo các bước sau trên macOS (hoặc máy có cài Command Line Tools):

### Bước 1: Kéo mã nguồn mới về
Mở Terminal trong thư mục repo:
```bash
cd "E:/WhateverXe build"
# Hủy các thay đổi cũ nếu cần trước khi pull
git checkout .
# Kéo commit mới nhất từ nhánh upstream acer/current của tác giả
git pull upstream acer/current
```

### Bước 2: Kiểm tra và áp dụng bản vá tự động
Chạy lệnh kiểm tra tính tương thích của patch:
```bash
git apply --check whateverxe_thinkpad_p1_gen5.patch
```
* Nếu không báo lỗi gì, áp dụng patch:
```bash
git apply whateverxe_thinkpad_p1_gen5.patch
```
* *(Nếu có conflict do tác giả đổi vị trí dòng code, mở file `.patch` và so sánh lại 4 vị trí ở Phần 3 để chèn lại bằng tay).*

### Bước 3: Biên dịch lại Kext
Chạy lệnh Xcode build ở chế độ Release:
```bash
xcodebuild -project WhateverXe.xcodeproj -configuration Release
```
File kext mới biên dịch xong sẽ nằm tại:
`build/Release/WhateverXe.kext`

### Bước 4: Sao chép Kext vào EFI OpenCore
Copy đè kext mới vào thư mục EFI trên USB hoặc ổ đĩa:
```bash
cp -R build/Release/WhateverXe.kext /Volumes/EFI/EFI/OC/Kexts/
```
Khởi động lại máy để tận hưởng phiên bản mới.
