# فایل‌های مستقل هر VM

تمام install.shها از ماشین مدیریت اجرا می‌شوند و Playbook مستقل همان پوشه را صدا می‌زنند. [ترتیب کامل نصب](../docs/install-a-to-z.md) را دنبال کنید.

| VM | IP | اسکریپت | Ansible | تنظیمات |
|---|---|---|---|---|
| [clickhouse01](clickhouse01/README.md) | 192.168.1.42 | [`install.sh`](clickhouse01/install.sh) | [`install.yml`](clickhouse01/install.yml) | [`vars.yml`](clickhouse01/vars.yml) |
| [haproxy01](haproxy01/README.md) | 192.168.1.5 | [`install.sh`](haproxy01/install.sh) | [`install.yml`](haproxy01/install.yml) | [`vars.yml`](haproxy01/vars.yml) |
| [k8s-master01](k8s-master01/README.md) | 192.168.1.10 | [`install.sh`](k8s-master01/install.sh) | [`install.yml`](k8s-master01/install.yml) | [`vars.yml`](k8s-master01/vars.yml) |
| [k8s-worker01](k8s-worker01/README.md) | 192.168.1.21 | [`install.sh`](k8s-worker01/install.sh) | [`install.yml`](k8s-worker01/install.yml) | [`vars.yml`](k8s-worker01/vars.yml) |
| [k8s-worker02](k8s-worker02/README.md) | 192.168.1.22 | [`install.sh`](k8s-worker02/install.sh) | [`install.yml`](k8s-worker02/install.yml) | [`vars.yml`](k8s-worker02/vars.yml) |
| [k8s-worker03](k8s-worker03/README.md) | 192.168.1.23 | [`install.sh`](k8s-worker03/install.sh) | [`install.yml`](k8s-worker03/install.yml) | [`vars.yml`](k8s-worker03/vars.yml) |
| [meilisearch01](meilisearch01/README.md) | 192.168.1.43 | [`install.sh`](meilisearch01/install.sh) | [`install.yml`](meilisearch01/install.yml) | [`vars.yml`](meilisearch01/vars.yml) |
| [minio01](minio01/README.md) | 192.168.1.28 | [`install.sh`](minio01/install.sh) | [`install.yml`](minio01/install.yml) | [`vars.yml`](minio01/vars.yml) |
| [monitoring01](monitoring01/README.md) | 192.168.1.30 | [`install.sh`](monitoring01/install.sh) | [`install.yml`](monitoring01/install.yml) | [`vars.yml`](monitoring01/vars.yml) |
| [nfs01](nfs01/README.md) | 192.168.1.24 | [`install.sh`](nfs01/install.sh) | [`install.yml`](nfs01/install.yml) | [`vars.yml`](nfs01/vars.yml) |

| نصب دستی طبق تصمیم شما | IP | بررسی اتصال |
|---|---|---|
| [kerio01](kerio01/README.md) | 192.168.1.4 | [verify.yml](kerio01/verify.yml) |
| [mssql01](mssql01/README.md) | 192.168.1.40 | [verify.yml](mssql01/verify.yml) |

نصب واقعی Kubernetes پس از آماده‌سازی چهار VM با [install-kubernetes.sh](../scripts/install-kubernetes.sh) انجام می‌شود؛ سپس [install-addons.sh](../scripts/install-addons.sh) ابزارهای داخل کلاستر را نصب می‌کند.
