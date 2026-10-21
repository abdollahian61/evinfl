# HAProxy روی Ubuntu 24.04

VM: `192.168.1.5`، چهار vCPU، رم ۸ گیگ، دیسک OS برابر ۳۰ گیگ و دیسک دوم ۵۰ گیگ. IP عمومی و کاربرد دیسک دوم هنوز مشخص نشده‌اند.

## نصب

```bash
sudo apt update
sudo apt install -y haproxy openssl
sudo install -d -m 700 /etc/haproxy/certs
```

## گواهی

مسیر گواهی در تنظیمات `/etc/haproxy/certs/default.pem` است و باید PEM شامل گواهی، زنجیره موردنیاز و کلید خصوصی متناظر باشد. برای تست اولیه می‌توان گواهی موقت زیر را ساخت؛ `app.example.com` دامنه نمونه است:

```bash
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -days 30 \
  -keyout /etc/haproxy/certs/default.key \
  -out /etc/haproxy/certs/default.crt \
  -subj '/CN=app.example.com' \
  -addext 'subjectAltName=DNS:app.example.com'
sudo sh -c 'cat /etc/haproxy/certs/default.crt /etc/haproxy/certs/default.key > /etc/haproxy/certs/default.pem'
sudo chmod 600 /etc/haproxy/certs/default.key /etc/haproxy/certs/default.pem
```

این فایل‌ها را خارج از Git نگه دار. در استقرار واقعی، گواهی معتبر دامنه و روش تمدید آن جایگزین این نمونه می‌شود.

## اعمال کانفیگ

از ریشه clone مخزن و پس از آماده‌شدن PEM:

```bash
sudo cp -a /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
sudo install -o root -g root -m 644 config/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

فقط پس از موفقیت اعتبارسنجی:

```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
sudo systemctl status haproxy --no-pager
```

IP ورکرها در کانفیگ با تصمیم فعلی پروژه هماهنگ است: `192.168.1.21`، `192.168.1.22` و `192.168.1.23`. پورت `30080` هنوز NodePort پیشنهادی سرویس HTTP در Traefik است؛ هنگام استقرار باید دقیقاً تطبیق داده شود.

HAProxy پورت ۸۰ را به HTTPS هدایت می‌کند؛ روی ۴۴۳ TLS را خاتمه می‌دهد و با HTTP به Workerها می‌فرستد. Host حفظ می‌شود. `X-Forwarded-For` از IP اتصال ورودی تنظیم می‌شود؛ اگر بعدها CDN یا پروکسی دیگری جلوی HAProxy اضافه شد، روش دریافت IP اصلی باید متناسب بازطراحی شود.

در فایروال آروان، ورودی عمومی TCP 80/443 به HAProxy و دسترسی خصوصی HAProxy به TCP 30080 ورکرها باید برقرار باشد. NodePort از اینترنت مستقیماً در دسترس قرار نمی‌گیرد. در Traefik اعتماد به headerهای forwarded باید به `192.168.1.5` محدود شود.

تا زمان آماده‌شدن سرویس Traefik روی NodePort، پاسخ 503 محتمل است. health check فعلی TCP است و سلامت Route یا خود اپلیکیشن را تضمین نمی‌کند؛ آزمون HTTP با دامنه واقعی در راهنمای نهایی اضافه می‌شود.

## منابع

- [Ubuntu 24.04 HAProxy package](https://packages.ubuntu.com/noble/net/haproxy)
- [HAProxy HTTP/TLS configuration](https://www.haproxy.com/documentation/haproxy-configuration-tutorials/protocol-support/http/)
