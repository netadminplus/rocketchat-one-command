<div align="right">

**فارسی** | [English](README.en.md)

</div>

---

# نصب یک دستوری RocketChat

<div dir="rtl">

**نصب آسان RocketChat با Docker، SSL و پیکربندی خودکار**

ساخته شده توسط [رامتین - نت ادمین پلاس](https://netadminplus.com)

[یوتیوب](https://youtube.com/@netadminplus) • [وبسایت](https://netadminplus.com) • [اینستاگرام](https://instagram.com/netadminplus)

---

## امکانات

- نصب با یک دستور
- SSL خودکار با Let's Encrypt و تمدید اتوماتیک
- مبتنی بر Docker
- پشتیبانی از Docker registry mirror برای ایران
- تولید خودکار رمزهای امن
- بررسی سیستم قبل از نصب
- بررسی DNS دامنه
- پشتیبانی از Ubuntu، Debian، Rocky Linux، CentOS، AlmaLinux
- ساختار منظم فایل‌ها
- قابلیت نصب با هشدار اگر سیستم شرایط کامل را نداشته باشد

---

## پیش‌نیازها

**سخت‌افزار:**
- حداقل 2GB رم (4GB پیشنهادی)
- حداقل 2 هسته CPU (پیشنهادی)
- حداقل 20GB فضای خالی

**نرم‌افزار:**
- Ubuntu 20.04+، Debian 10+، Rocky Linux 8+، CentOS 7+، AlmaLinux 8+
- دسترسی root یا sudo
- دامنه یا ساب‌دامنه که به IP سرور شما اشاره کند
- پورت‌های 80 و 443 باز باشند

---

## نصب

### روش پیشنهادی: دانلود و اجرا

</div>

```bash
curl -fsSL [https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/rocketchat-installer.sh](https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/rocketchat-installer.sh) -o rocketchat-installer.sh
chmod +x rocketchat-installer.sh
sudo ./rocketchat-installer.sh
```

<div dir="rtl">

### روش جایگزین: نصب یک خطی

⚠️ **توجه**: این روش ممکن است با ورودی تعاملی مشکل داشته باشد. روش بالا را امتحان کنید.

</div>

```bash
curl -fsSL [https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/rocketchat-installer.sh](https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/rocketchat-installer.sh) | sudo bash
```

<div dir="rtl">

### یا clone کردن از گیت‌هاب

</div>

```bash
git clone [https://github.com/netadminplus/rocketchat-one-command.git](https://github.com/netadminplus/rocketchat-one-command.git)
cd rocketchat-one-command
chmod +x rocketchat-installer.sh
sudo ./rocketchat-installer.sh
```

<div dir="rtl">

---

## مراحل نصب

اسکریپت این کارها را انجام می‌دهد:

1. بررسی رم، CPU و دیسک
2. تشخیص نوع لینوکس
3. بررسی دسترسی به Docker Hub
4. نصب یا آپدیت Docker و Docker Compose
5. دریافت دامنه از شما
6. بررسی DNS دامنه
7. دریافت ایمیل (اختیاری، برای اطلاع‌رسانی SSL)
8. دریافت آدرس Docker registry mirror (در صورت نیاز)
9. تولید رمزهای امن MongoDB
10. ساخت فایل Docker Compose
11. دریافت گواهی SSL از Let's Encrypt
12. تنظیم تمدید خودکار گواهی
13. نمایش دستورات فایروال
14. راه‌اندازی کانتینرها
15. نمایش اطلاعات دسترسی و رمزها

---

## ساختار فایل‌ها

بعد از نصب، این فایل‌ها در پوشه شما خواهند بود:

</div>

```
rocketchat-one-command/
├── docker-compose.yml       # تنظیمات Docker Compose
├── .env                      # متغیرها و رمزها
├── data/
│   ├── mongodb/             # فایل‌های دیتابیس MongoDB
│   ├── uploads/             # فایل‌های آپلود شده
│   └── certs/               # گواهی‌های SSL
└── rocketchat-installer.sh  # اسکریپت نصب
```

<div dir="rtl">

---

## تنظیمات

### مشاهده رمزها

تمام رمزها و تنظیمات در فایل `.env` ذخیره می‌شوند:

</div>

```bash
cat .env
```

<div dir="rtl">

### دسترسی به RocketChat

بعد از نصب:

</div>

```
آدرس: [https://your-domain.com](https://your-domain.com)
نکته: اولین کاربری که ثبت‌نام می‌کند، ادمین می‌شود
```

<div dir="rtl">

---

## تنظیم فایروال

اسکریپت دستورات فایروال را نمایش می‌دهد. مثال برای UFW:

</div>

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

<div dir="rtl">

---

## آپدیت

برای آپدیت RocketChat، فایل [UPDATE.md](docs/UPDATE.md) را ببینید.

---

## رفع مشکلات

برای مشکلات رایج و راه‌حل‌ها، فایل [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) را ببینید.

---

## فایل‌های مهم

- **`.env`** - شامل تمام رمزها (رمز MongoDB و غیره)
- **`docker-compose.yml`** - تنظیمات سرویس‌ها
- **`data/`** - تمام داده‌های دائمی (دیتابیس، آپلودها، گواهی‌ها)

### پشتیبان‌گیری

</div>

```bash
# بکاپ از پوشه data
tar -czf rocketchat-backup-$(date +%Y%m%d).tar.gz data/

# بکاپ از فایل env
cp .env .env.backup
```

<div dir="rtl">

---

## متوقف کردن / راه‌اندازی RocketChat

</div>

```bash
# متوقف کردن سرویس‌ها
docker compose down

# راه‌اندازی سرویس‌ها
docker compose up -d

# مشاهده لاگ‌ها
docker compose logs -f

# ریستارت سرویس‌ها
docker compose restart
```

<div dir="rtl">

---

## حذف کامل

</div>

```bash
# متوقف و حذف کانتینرها
docker compose down -v

# حذف داده‌ها (⚠️ این کار همه چیز را پاک می‌کند!)
rm -rf data/

# حذف Docker (اختیاری)
# Ubuntu/Debian: sudo apt remove docker-ce docker-ce-cli containerd.io
# Rocky/CentOS: sudo dnf remove docker-ce docker-ce-cli containerd.io
```

<div dir="rtl">

---

## پشتیبانی

- 📺 **یوتیوب**: [@netadminplus](https://youtube.com/@netadminplus)
- 🌐 **وبسایت**: [netadminplus.com](https://netadminplus.com)
- 📸 **اینستاگرام**: [@netadminplus](https://instagram.com/netadminplus)
- 🐛 **گزارش مشکل**: [GitHub Issues](https://github.com/netadminplus/rocketchat-one-command/issues)

---

## لایسنس

MIT License - استفاده و تغییر آزاد است

---

## سازنده

**رامتین - نت ادمین پلاس**

کمک به جامعه ایرانی برای استقرار ابزارهای ارتباطی متن‌باز

[یوتیوب](https://youtube.com/@netadminplus) • [وبسایت](https://netadminplus.com) • [اینستاگرام](https://instagram.com/netadminplus)

---

## حمایت از پروژه

اگر این پروژه به شما کمک کرد:
- ⭐ به این ریپازیتوری ستاره بدهید
- 📺 کانال [نت ادمین پلاس](https://youtube.com/@netadminplus) را سابسکرایب کنید
- 📢 با دوستان و همکاران به اشتراک بگذارید

---

**ساخته شده با ❤️ برای جامعه تکنولوژی ایران**

</div>
