# مراجعة الإشعارات — Flutter فقط

## الحالة الحالية

أصبح التطبيق Flutter-only. لا يستخدم التطبيق Expo أو Expo Push Service.

عند وجود جلسة مستخدم، يبدأ `NotificationsRuntime` اشتراكًا مباشرًا عبر Supabase Realtime على جدول `public.notifications`، ويعرض الإدراج الجديد كإشعار نظام محلي عبر `flutter_local_notifications`. كما تبقى قائمة الإشعارات وحالة القراءة محفوظتين في Supabase.

## ما تم إزالته

- تطبيق Expo/React Native بالكامل من `apps/mobile`.
- تسجيل Expo Push Token.
- استدعاء `register_push_device` المرتبط بـ Expo.
- Trigger قاعدة البيانات الذي كان يرسل إلى `https://exp.host/--/api/v2/push/send`.

## ما تم اعتماده

- اشتراك Flutter مباشر في Realtime مع فلتر المستخدم الحالي.
- قناة إشعارات Android باسم `alshaeri_notifications`.
- طلب صلاحية الإشعارات على Android.
- إشعار محلي عند وصول سجل جديد، مع فتح المهمة المرتبطة عند الضغط عليه.
- ترحيل قاعدة البيانات `070_remove_expo_push.sql` لإيقاف مسار Expo وإبقاء سجل الإشعارات الداخلي.

## القيد الحالي

إشعارات Realtime والإشعارات المحلية تعمل عندما تكون نسخة Flutter قيد التشغيل وقادرة على الاتصال بـ Supabase. لا يمكن ضمان إشعار عند إغلاق التطبيق أو إيقاف العملية بهذه الآلية وحدها.

لإضافة Push حقيقي عند إغلاق التطبيق، يلزم إعداد Firebase/FCM لـAndroid وAPNs لـiOS، ثم إضافة تسجيل الرمز الأصلي وإرسال FCM/APNs من Edge Function أو خدمة خادم آمنة. لا يجوز وضع مفتاح خدمة Firebase داخل التطبيق أو المستودع. لا يُعد هذا الجزء مكتملًا حتى تتوفر بيانات مشروع Firebase وتُختبر نسخة على جهاز حقيقي.
