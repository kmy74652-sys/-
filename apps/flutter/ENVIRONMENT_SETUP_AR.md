

## محاولة بديلة عبر QEMU

تم تثبيت `qemu-user-static` وتجهيز جذر Ubuntu amd64 مصغر في `/home/ubuntu/amd64-root`. نجح تشغيل Dart x64 البسيط عبر QEMU وإظهار إصدار Dart، لكن تشغيل Flutter Tool نفسه انتهى بخطأ `SIGSEGV` داخل المحاكاة. لذلك لا تُعد هذه طريقة صالحة للتحليل أو الاختبار أو بناء APK.

النتيجة العملية: يلزم Linux x64 حقيقي أو Cloud Computer x64 لتشغيل Flutter Tool، وليس مجرد محاكاة user-mode على هذا ARM64 Sandbox.
