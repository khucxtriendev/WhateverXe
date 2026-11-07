#!/bin/bash
# ==============================================================================
# Script tự động cập nhật WhateverXe và áp dụng bản vá cho ThinkPad P1 Gen 5
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PATCH_FILE="$SCRIPT_DIR/whateverxe_thinkpad_p1_gen5.patch"

REMOTE_SOURCE="upstream"
if ! git remote get-url upstream >/dev/null 2>&1; then
    REMOTE_SOURCE="origin"
fi

echo "=========================================================="
echo " 1. Kéo mã nguồn mới nhất từ remote $REMOTE_SOURCE (nhánh acer/current)..."
echo "=========================================================="
git fetch "$REMOTE_SOURCE"

echo "[*] Reset working tree về trạng thái sạch..."
git checkout .

echo "[*] Kéo commit mới nhất từ $REMOTE_SOURCE/acer/current về..."
git pull "$REMOTE_SOURCE" acer/current

echo ""
echo "=========================================================="
echo " 2. Áp dụng bản vá whateverxe_thinkpad_p1_gen5.patch..."
echo "=========================================================="
if [ ! -f "$PATCH_FILE" ]; then
    echo "[!] Lỗi: Không tìm thấy file $PATCH_FILE"
    exit 1
fi

if git apply --check "$PATCH_FILE"; then
    git apply "$PATCH_FILE"
    echo "[+] Đã áp dụng bản vá thành công vào mã nguồn!"
else
    echo "[!] CẢNH BÁO: Không thể áp dụng tự động (có thể do code mới bị dịch chuyển dòng)."
    echo "    Vui lòng mở THINKPAD_P1_GEN5_PATCH_GUIDE.md để kiểm tra và sửa tay 4 vị trí."
    exit 1
fi

echo ""
echo "=========================================================="
echo " 3. Biên dịch lại WhateverXe.kext (Release)..."
echo "=========================================================="
if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -project WhateverXe.xcodeproj -configuration Release -quiet
    echo "[+] Biên dịch hoàn tất!"
    echo "    Kext mới nằm tại: $SCRIPT_DIR/build/Release/WhateverXe.kext"
else
    echo "[!] Máy hiện tại chưa có xcodebuild (chỉ có trên macOS)."
    echo "    Bạn có thể mang thư mục này sang macOS để chạy xcodebuild."
fi

echo ""
echo "=========================================================="
echo " HOÀN TẤT! Hãy copy WhateverXe.kext vào EFI/OC/Kexts."
echo "=========================================================="
