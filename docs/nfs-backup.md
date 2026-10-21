# بکاپ کل داده‌های NFS در MinIO

این اسکریپت روی `nfs01` با IP `192.168.1.24` اجرا می‌شود و تمام فایل‌های share، شامل PVCهایی که Pod فعال ندارند، را از مسیر محلی می‌خواند. مقصد یک مخزن Restic در bucket اختصاصی `nfs-backup` روی MinIO است. Velero جداگانه منابع Kubernetes را بکاپ می‌گیرد.

فرض مسیر: دیسک داده NFS روی `/srv/nfs` mount شده و تمام داده‌های موردنظر زیر همین مسیر هستند. `BACKUP_SOURCE` و `DATA_MOUNT` باید با نصب واقعی تطبیق داده شوند. اسکریپت با `--one-file-system` از filesystem منبع عبور نمی‌کند؛ اگر داده روی mountهای دیگری نیز قرار دارد، باید دامنه بکاپ متناسب با آن اصلاح شود.

## نصب روی سرور NFS

از ریشه clone این مخزن:

```bash
sudo apt update
sudo apt install -y restic openssl ca-certificates util-linux
sudo install -m 700 scripts/backup/nfs-to-minio.sh /usr/local/sbin/nfs-to-minio.sh
```

در MinIO، bucket به نام `nfs-backup` و Access Key با دسترسی خواندن، نوشتن و حذف فقط روی همین bucket بساز. bucket مربوط به Velero مستقل باشد.

تنظیمات اولیه را فقط هنگام اولین نصب کپی کن؛ در نصب‌های بعدی فایل تنظیمات موجود را ویرایش کن تا کلیدها از بین نروند:

```bash
sudo install -o root -g root -m 600 config/backup/nfs-backup.env.example /etc/nfs-backup.env
sudo nano /etc/nfs-backup.env
```

مقادیر `CHANGE_ME` را با کلید اختصاصی MinIO جایگزین کن. Endpoint نمونه `http://192.168.1.28:9000` روی شبکه خصوصی است؛ اگر TLS برای MinIO تنظیم شد، URL و اعتماد به CA را متناسب تغییر بده.

یک بار رمز مخزن را تولید کن؛ دستور زیر فایل موجود را بازنویسی نمی‌کند:

```bash
sudo bash -c 'umask 077; set -o noclobber; openssl rand -base64 48 > /etc/nfs-backup.password'
```

یک نسخه امن از رمز و تنظیمات موردنیاز برای بازیابی را خارج از این VM نگه دار. بدون رمز مخزن، داده رمزنگاری‌شده قابل بازیابی نیست. رمز و Access Key را در Git ثبت نکن.

مخزن را فقط بار اول ایجاد کن، سپس بکاپ را اجرا کن:

```bash
sudo /usr/local/sbin/nfs-to-minio.sh init
sudo /usr/local/sbin/nfs-to-minio.sh
sudo /usr/local/sbin/nfs-to-minio.sh snapshots
```

## اجرا با cron

نمونه ساعت ۰۲:۰۰ به وقت تنظیم‌شده سرور است؛ ساعت هنوز تصمیم نهایی پروژه نیست. پس از موفقیت اجرای دستی، می‌توان از فایل system cron استفاده کرد:

```bash
sudo install -o root -g root -m 644 config/cron/nfs-backup /etc/cron.d/nfs-backup
```

این قالب دارای ستون `root` است و برای `/etc/cron.d/` نوشته شده. اگر از `sudo crontab -e` استفاده می‌کنی، خط متناظر بدون ستون کاربر است:

```cron
0 2 * * * umask 077; /usr/local/sbin/nfs-to-minio.sh >> /var/log/nfs-backup.log 2>&1
```

فقط یکی از دو روش را فعال کن. فایل لاگ را با سیاست logrotate سرور مدیریت کن.

## نگهداری و رفتار خطا

- هر snapshot نمای کامل فایل‌های پوشش‌داده‌شده دارد؛ محتوا در مخزن deduplicate و رمزنگاری می‌شود.
- بعد از بکاپ موفق، سیاست `--keep-within 14d --keep-last 1 --prune` اجرا می‌شود. بازه ۱۴روزه نسبت به جدیدترین snapshot محاسبه می‌شود.
- اگر mount دیسک داده موجود نباشد یا خواندن منبع ناقص شود، اسکریپت متوقف می‌شود و مرحله retention اجرا نمی‌شود.
- `flock` مانع هم‌زمانی عملیات همین اسکریپت روی یک سرور می‌شود.
- حذف objectهای مخزن باید با Restic مدیریت شود؛ حذف بر اساس سن object با Lifecycle در MinIO می‌تواند مخزن را خراب کند. برای این bucket چنین قانون حذفی تنظیم نکن.
- موفقیت بکاپ و خطاها باید در پایش عملیاتی دنبال شوند؛ صرف وجود cron تضمین موفقیت نیست.
- بکاپ فایل‌های زنده، snapshot اتمیک یا تضمین سازگاری اپلیکیشن نیست. اگر برنامه به consistency خاص نیاز دارد، quiesce یا backup hook آن جداگانه طراحی شود.
- دیسک ۱۰۰ گیگی MinIO هنوز از نظر حجم مصرف‌شده و نرخ تغییر داده ارزیابی نشده است.

## بررسی و بازیابی آزمایشی

```bash
sudo /usr/local/sbin/nfs-to-minio.sh check
sudo /usr/local/sbin/nfs-to-minio.sh restore /srv/restore-test
```

مقصد Restore باید جدید یا خالی باشد. ساختار مسیر اصلی زیر مقصد بازسازی می‌شود؛ برای منبع `/srv/nfs`، فایل‌ها معمولاً زیر `/srv/restore-test/srv/nfs` قرار می‌گیرند. ابتدا فضای آزاد مقصد و محتوای بازیابی را بررسی کن، سپس برنامه انتقال به محیط عملیاتی را تعیین کن. برای آزمون بزرگ، فضای جداگانه لازم است.

`check` ساختار مخزن را بررسی می‌کند؛ اعتبارسنجی کامل داده و آزمون Restore باید طبق برنامه عملیاتی جداگانه اجرا شوند.

## منابع

- [Restic: preparing a repository / S3-compatible storage](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html)
- [Restic: retention and prune](https://restic.readthedocs.io/en/stable/060_forget.html)
- [Restic: scripting and exit codes](https://restic.readthedocs.io/en/stable/075_scripting.html)

اسکریپت روی سرورهای واقعی پروژه اجرا نشده است؛ نتیجه بررسی‌های محلی جای تست اتصال و بازیابی واقعی را نمی‌گیرد.
