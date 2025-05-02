

## 📌 معرفی
این اسکریپت یک راه‌حل خودکار برای راه‌اندازی سرور VPN مبتنی بر پروتکل OpenConnect (ocserv) با احراز هویت RADIUS ارائه می‌دهد. اسکریپت به گونه ای طراحی شده که تمام مراحل نصب و پیکربندی را به صورت خودکار انجام می‌دهد.

برای رادیوس سرور از این اسکریپت میتوانید استفاده کنید
```
bash <(curl -s https://raw.githubusercontent.com/aliamg1356/IBSng-manager/refs/heads/main/ibsng.sh --ipv4)
```

## 🎯 ویژگی‌های کلیدی
- راه‌اندازی سریع سرور VPN با احراز هویت RADIUS
- پیکربندی خودکار گواهی SSL از Let's Encrypt
- استفاده از داکر برای پیاده‌سازی آسان و قابل حمل
- رابط کاربری تعاملی با استفاده از `whiptail`
- پشتیبانی از DNS خصوصی (AdGuard DNS)
- سازگاری با کلاینت‌های Cisco AnyConnect

## 🔧 مراحل اجرای اسکریپت

### 1. بررسی پیش‌نیازها
اسکریپت ابتدا ابزارهای مورد نیاز را بررسی می‌کند:
- `docker` و `docker-compose` برای containerization
- `certbot` برای دریافت گواهی SSL
- `curl` برای دانلود فایل‌ها
- `whiptail` برای رابط کاربری تعاملی

### 2. دریافت اطلاعات کاربر
از کاربر اطلاعات زیر را دریافت می‌کند:
- نام دامنه (برای گواهی SSL)
- آدرس ایمیل (برای Let's Encrypt)
- محدوده IP برای شبکه VPN
- آدرس سرور RADIUS و رمز مشترک

### 3. دریافت گواهی SSL
با استفاده از `certbot` یک گواهی SSL رایگان از Let's Encrypt دریافت می‌کند.

### 4. ساختار دایرکتوری
ساختار دایرکتوری مورد نیاز را ایجاد می‌کند:
```
/opt/ocs/
├── config/
├── radius/
└── docker-compose.yml
```

### 5. پیکربندی فایل‌ها
- **docker-compose.yml**: پیکربندی سرویس ocserv در داکر
- **ocserv.conf**: فایل پیکربندی اصلی سرور VPN
- **radiusclient.conf**: پیکربندی اتصال به سرور RADIUS
- **servers**: اطلاعات سرور RADIUS و رمز مشترک

## ⚙️ تنظیمات فنی ocserv
- استفاده از TLS با اولویت‌های امنیتی بالا
- محدودیت اتصال همزمان (max-same-clients)
- زمان‌بندی‌های بهینه برای اتصال (keepalive, dpd)
- پشتیبانی از IPv4 با محدوده IP قابل تنظیم
- DNS پیش‌فرض: AdGuard DNS (94.140.14.14, 94.140.15.15)
- سازگاری با کلاینت‌های Cisco AnyConnect

## 🚀 نحوه اجرا
1. اسکریپت را با دستور زیر اجرا کنید:
```bash
bash <(curl -s https://raw.githubusercontent.com/aliamg1356/openconnect-installer/refs/heads/main/setup_ocserv.sh --ipv4)
```

2. پس از تکمیل نصب، با دستور زیر سرویس را راه‌اندازی کنید:
```bash
cd /opt/ocs && docker-compose up -d
```

## 📝 نکات مهم
- پورت 443 باید در فایروال باز باشد.
- سرور RADIUS باید از قبل راه‌اندازی شده باشد.
- برای به‌روزرسانی گواهی SSL، می‌توانید از `certbot renew` استفاده کنید.

## 📜 مجوز
این اسکریپت تحت مجوز MIT منتشر شده است.

---

## 💰 حمایت مالی

ما از حمایت شما برای توسعه و بهبود مستمر پروژه قدردانی می‌کنیم:

<div align="center">

| شبکه         | نوع ارز       | آدرس کیف پول                              | آیکون       |
|--------------|--------------|------------------------------------------|------------|
| **Tron**     | TRX (TRC20)  | `TMXRpCsbz8PKzqN4koXiErawdLXzeinWbQ`     | <img src="https://cryptologos.cc/logos/tron-trx-logo.png" width="20"> |
| **Ethereum** | USDT (ERC20) | `0xD4cEBA0cFf6769Fb9EFE4606bE59C363Ff85BF76` | <img src="https://cryptologos.cc/logos/tether-usdt-logo.png" width="20"> |

</div>

<div align="center" style="margin-top: 20px;">
  <p>🙏 از اعتماد و حمایت ارزشمند شما سپاسگزاریم</p>
  <p>هر میزان کمک مالی، انگیزه‌ای برای توسعه و ارتقای پروژه خواهد بود</p>
</div>

