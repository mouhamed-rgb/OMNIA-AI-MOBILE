# OMNIA AI MOBILE

تطبيق Android مستقل مبني باستخدام Flutter وDart، ويتصل بخادم Backend مستقل يستخدم Groq API.

## بنية المشروع

- `flutter_app/`: تطبيق Flutter.
- `backend/`: API على Vercel.
- `.github/workflows/build-apk.yml`: بناء APK تلقائياً عبر GitHub Actions.

## 1. نشر Backend على Vercel

1. افتح Vercel وأنشئ مشروعاً جديداً واربطه بهذا المستودع.
2. في إعدادات المشروع اختر **Root Directory** واجعله `backend`.
3. من **Settings → Environment Variables** أضف:
   - الاسم: `GROQ_API_KEY`
   - القيمة: مفتاح Groq الخاص بك.
4. أعد النشر، ثم انسخ رابط Backend المنشور، مثال: `https://your-backend.vercel.app`.

**مهم:** لا تضع مفتاح Groq داخل تطبيق Flutter أو في ملفات GitHub أو في متغيرات عامة. خزّنه في Vercel فقط. إذا سبق أن شاركت مفتاحاً في مكان عام، ألغِه وأنشئ مفتاحاً جديداً.

## 2. إعداد GitHub Actions

1. افتح المستودع ثم **Settings → Secrets and variables → Actions → Variables**.
2. اختر **New repository variable**.
3. الاسم: `API_BASE_URL`.
4. القيمة: رابط Backend المنشور دون `/` في النهاية.
5. احفظ المتغير.

## 3. بناء APK

1. افتح تبويب **Actions** في المستودع.
2. اختر **Build OMNIA AI Mobile APK**.
3. اضغط **Run workflow** ثم أكد التشغيل.
4. بعد ظهور علامة النجاح، افتح تشغيل الـ workflow.
5. نزّل Artifact باسم `omnia-ai-mobile-release`. يحتوي ملف APK.

## تشغيل Flutter محلياً

من مجلد `flutter_app`:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://YOUR-BACKEND.vercel.app
```

لا يحتوي المستودع على مفتاح API. يجب نشر Backend وضبط `API_BASE_URL` قبل بناء نسخة APK قابلة للاتصال.
