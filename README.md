# evinfl

مستندات، اسکریپت‌ها و تنظیمات زیرساخت روی ابر آروان.

**وضعیت: پیش‌نویس در حال تکمیل.** مشخصات زیر با تصمیم‌های فعلی هماهنگ‌اند. طرح نهایی، راهنمای نصب کامل کلاستر و فایل قابل‌ویرایش Visio پس از اعلام «final» تهیه می‌شوند.

## فایل‌ها

| فایل | کاربرد |
|---|---|
| [مشخصات زیرساخت](docs/infrastructure.md) | ماشین‌ها، شبکه، ترتیب نصب و موارد باز |
| [کانفیگ HAProxy](config/haproxy/haproxy.cfg) | دریافت HTTPS و ارسال HTTP به NodePort ورکرها |
| [راهنمای HAProxy](docs/haproxy.md) | نصب بسته، گواهی، بررسی تنظیمات و اجرای سرویس |
| [اسکریپت بکاپ NFS](scripts/backup/nfs-to-minio.sh) | بکاپ کل پوشه داده NFS در MinIO با Restic |
| [راهنمای بکاپ NFS](docs/nfs-backup.md) | تنظیمات، اجرا، cron و بازیابی |
| [تنظیمات نمونه بکاپ](config/backup/nfs-backup.env.example) | مسیرها و محل جایگزینی Access Key |
| [نمونه cron](config/cron/nfs-backup) | اجرای روزانه با کاربر root |

فایل‌های دارای رمز، کلید خصوصی، kubeconfig مدیریتی و لایسنس واقعی باید خارج از Git نگهداری شوند. نمونه‌های موجود فقط مقدار جایگزین دارند.

## تصمیم‌های اصلی

- Kubernetes با یک Control Plane و سه Worker، نصب با Kubespray.
- Cilium پس از آماده‌سازی کلاستر، با Helm و جایگزینی kube-proxy نصب می‌شود.
- Gateway API با کنترلر Traefik؛ ورودی از HAProxy به NodePort سرویس Traefik.
- خاتمه TLS روی HAProxy و ارتباط HTTP در مسیر داخلی وب.
- فقط Kerio و HAProxy دارای IP عمومی هستند؛ سایر ماشین‌ها از Kerio به اینترنت دسترسی می‌گیرند.
- Zabbix و Grafana روی VM مانیتورینگ/مدیریت؛ Prometheus Stack داخل کلاستر؛ بدون Runner روی VM مدیریت.
- بکاپ فعلی: منابع Kubernetes با Velero، و کل پوشه داده NFS با Restic؛ مقصد MinIO، روزانه با نگهداری ۱۴روزه.

اسکریپت‌ها در محیط واقعی آروان اجرا نشده‌اند. IPهای خصوصی ثبت‌شده تصمیم‌های فعلی پروژه‌اند؛ دامنه، IP عمومی و برخی مسیرها هنوز نمونه هستند.
