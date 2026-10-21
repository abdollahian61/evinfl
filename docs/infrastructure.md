# مشخصات زیرساخت — پیش‌نویس

## ماشین‌های مجازی

نام ماشین‌ها پیشنهادی است. تمام ظرفیت دیسک‌ها بر حسب گیگابایت است. ستون اول دیسک، سیستم‌عامل و ستون دوم دیسک مجزا است.

| ماشین | IP خصوصی | سیستم‌عامل/محصول | vCPU | RAM (GB) | دیسک OS | دیسک دوم | نقش |
|---|---|---|---:|---:|---:|---:|---|
| kerio01 | 192.168.1.4 | Kerio Control | 4 | 8 | 30 | — | VPN و Gateway/NAT خروج اینترنت |
| haproxy01 | 192.168.1.5 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 50 | ورودی عمومی HTTPS |
| k8s-master01 | 192.168.1.10 | Ubuntu 24.04 LTS | 4 | 8 | 30 | — | Control Plane و etcd |
| k8s-worker01 | 192.168.1.21 | Ubuntu 24.04 LTS | 6 | 12 | 30 | 50 | Worker |
| k8s-worker02 | 192.168.1.22 | Ubuntu 24.04 LTS | 6 | 12 | 30 | 50 | Worker |
| k8s-worker03 | 192.168.1.23 | Ubuntu 24.04 LTS | 6 | 12 | 30 | 50 | Worker |
| nfs01 | 192.168.1.24 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 100 | فضای PV/PVC کلاستر |
| minio01 | 192.168.1.28 | Ubuntu 24.04 LTS / MinIO AIStor | 4 | 8 | 30 | 100 | مخزن بکاپ تک‌نود |
| monitoring01 | 192.168.1.30 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 100 | Zabbix، Grafana و مدیریت DevOps |
| mssql01 | 192.168.1.40 | Windows Server 2025 / SQL Server 2019 Standard | 8 | 16 | 100 | 500 | دیتابیس؛ نصب توسط مالک پروژه |
| clickhouse01 | 192.168.1.42 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 100 | ClickHouse مستقل از کلاستر |
| meilisearch01 | 192.168.1.43 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 100 | Meilisearch مستقل از کلاستر |

روی Workerها، دیسک `sdb` برای داده‌های containerd و kubelet در نظر گرفته شده است. نام واقعی دستگاه‌ها، UUID و mountها باید پیش از اجرای دستورهای دیسک بررسی شود.

## شبکه و دسترسی

- تنها Kerio و HAProxy IP عمومی دارند؛ آدرس عمومی هنوز تعیین نشده است.
- حداکثر ۱۰ کاربر هم‌زمان به Kerio VPN متصل می‌شوند و دسترسی مدیریتی مستقیم به IP خصوصی VMها دارند. برای Linux از SSH استفاده می‌شود؛ روش مدیریت Windows جداگانه تعیین می‌شود.
- خروج اینترنت ماشین‌های خصوصی از طریق Kerio با IP خصوصی `192.168.1.4` در نظر گرفته شده است.
- خروج و مسیر برگشت ترافیک روی VMهای دارای IP عمومی باید در تنظیمات نهایی جداگانه بررسی شود.
- دسترسی سرویس NFS محدود به نودهای موردنیاز Kubernetes است؛ سایر VMها از share استفاده نمی‌کنند. دسترسی SSH مدیریتی مستقل از دسترسی به share است.
- مقدار subnet mask، رنج VPN، DNS و NTP هنوز مشخص نشده‌اند. از روی IPها نباید قطعی فرض کرد subnet برابر `/24` است.
- پشتیبانی آروان از ایمیج Kerio، کارت‌های شبکه و مسیریابی توسط VM/Gateway، همراه با قواعد امنیت پورت و مسیر برگشت، باید پیش از پیاده‌سازی تأیید شود.

## Kubernetes

| مورد | تصمیم فعلی |
|---|---|
| نسخه هدف | Kubernetes 1.36.4؛ نسخه‌های دیگر در config/versions.env |
| ابزار نصب | Kubespray؛ مبنای سازگار بررسی‌شده v2.32.0 |
| Runtime | containerd 2.3.5 مطابق bundle Kubespray |
| CNI | Cilium با Helm؛ نسخه Helm chart ثابت 1.20.3 |
| kube-proxy | از ابتدا نصب نمی‌شود؛ Cilium با `kubeProxyReplacement` فعال |
| Pod CIDR | `10.244.0.0/16` |
| Service CIDR | `10.96.0.0/16` |
| ورودی وب | Gateway API با کنترلر Traefik |
| NodePort پیشنهادی HTTP | `30080` |
| ذخیره‌سازی اپلیکیشن‌ها | NFS روی `192.168.1.24` با provisioner/CSI مناسب |
| پایش داخل کلاستر | Metrics Server و Prometheus Stack |

ترتیب موردنظر:

1. آماده‌سازی سیستم‌عامل، شبکه و دیسک‌ها.
2. نصب کلاستر با Kubespray، با مدیریت CNI توسط Helm و بدون kube-proxy.
3. نصب Cilium و بررسی Ready شدن نودها، DNS، Serviceها و NodePort.
4. نصب CRDهای Gateway API، Traefik و Routeها؛ اتصال HAProxy به سه Worker.
5. نصب درایور/provisioner مربوط به NFS و StorageClass.
6. نصب Metrics Server، Prometheus Stack و Velero.

پارامترهای دقیق Kubespray و مراحل وابسته به آماده‌شدن CNI باید روی tag انتخابی بررسی شوند؛ صرفاً نصب پیش‌فرض و تعویض بعدی CNI مدنظر نیست. API خصوصی Kubernetes، `k8sServiceHost` و `k8sServicePort` باید برای نصب Cilium بدون kube-proxy مشخص شوند.

مسیر وب: کاربر HTTPS را به HAProxy می‌فرستد؛ HAProxy با HTTP به NodePort سه Worker متصل می‌شود؛ Traefik مطابق Gateway API درخواست را به workload می‌رساند. Header اصلی Host حفظ می‌شود. اعتماد به `X-Forwarded-*` در Traefik باید محدود به IP خصوصی HAProxy باشد.

## مانیتورینگ و مدیریت

- Zabbix و Grafana روی `monitoring01` برای پایش دارایی‌ها.
- ابزارهای مدیریت Kubernetes شامل kubectl، Helm، Ansible و Kubespray روی همین ماشین.
- CI/CD Runner روی این ماشین اجرا نمی‌شود.
- Prometheus Stack داخل کلاستر است؛ داده‌ها روی Local PV در Worker01 با retention هفت‌روز و سقف 6GB قرار دارند. Grafana بیرونی از NodePort خصوصی 30900 استفاده می‌کند.

## بکاپ

- MinIO AIStor تک‌نود، آخرین نسخه پایدار در زمان نصب با ثبت نسخه دقیق.
- لایسنس تجاری و پشتیبانی رسمی درخواست شده؛ تهیه/فعال‌سازی هنوز انجام نشده است.
- منابع Kubernetes با Velero در bucket جداگانه؛ کل پوشه داده NFS با Restic در bucket `nfs-backup`.
- بکاپ روزانه با نگهداری ۱۴روزه.
- بکاپ دیتابیس‌های مستقل فعلاً در دامنه اجرایی این مرحله نیست.
- ظرفیت ۱۰۰ گیگی MinIO تصمیم اولیه است؛ کفایت آن به حجم واقعی و تغییرات داده‌ها وابسته است.
- روش بکاپ مستقل etcd/Control Plane و آزمون بازیابی باید در راهنمای نهایی تعیین شود؛ بکاپ منابع Velero به‌تنهایی تصویر کامل ماشین Control Plane محسوب نمی‌شود.

## موارد باز برای نهایی‌سازی

- IPهای عمومی، subnet mask، رنج VPN، DNS، NTP و دامنه‌ها.
- کانفیگ نهایی شبکه آروان و قواعد فایروال/مسیر برگشت.
- اجرای نسخه‌های ثابت config/versions.env و کنترل سازگاری در محیط واقعی.
- آزمون MTU خودکار و VXLAN در شبکه واقعی آروان؛ تنظیمات در config/helm/cilium.yaml.
- تأیید نام واقعی sdb پیش از فرمت؛ دیسک دوم HAProxy برای log انتخاب شده است.
- پذیرش عملی NFS CSI، local PV متریک‌ها و اتصال Grafana طبق راهنمای اجرا.
- فعال‌سازی لایسنس MinIO، ساخت کلیدها و آزمون Restore؛ زمان‌بندی‌ها در راهنمای اجرا مشخص‌اند.
- نقاط تک‌خرابی و مسیر ارتقای HA؛ تعداد فعلی VMها تغییر نمی‌کند مگر با تصمیم مالک پروژه.
- خروجی Visio پس از اعلام «final»؛ [راهنمای نصب](install-a-to-z.md) اکنون موجود است.

## منابع فنی

- [Kubespray v2.32.0](https://github.com/kubernetes-sigs/kubespray/releases/tag/v2.32.0)
- [Cilium Kubernetes compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
- [Cilium kube-proxy replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
- [Traefik Gateway API](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/)
- [MinIO AIStor licenses](https://docs.min.io/aistor/operations/licenses/)
