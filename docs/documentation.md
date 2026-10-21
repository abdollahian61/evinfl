# Infrastructure Deployment Guide

> **Status:** Production-oriented deployment runbook. Commands and configuration examples must be validated against the target environment before execution.


This runbook is executed from the `monitoring01` management host. All Linux systems run Ubuntu 24.04. The repository is prepared for deployment and validation; however, no installation has been performed on the production VMs. Hardware specifications are documented in the [infrastructure matrix](infrastructure.md), with per-VM details available in the [VM inventory](../vms/README.md). Kerio Control and SQL Server are intentionally installed and managed manually.

## 1. Network and Prerequisites

در آروان ابتدا شبکه خصوصی، NICها، قوانین امنیتی و مسیر برگشت را تنظیم کنید. تنها Kerio `.4` و HAProxy `.5` IP عمومی دارند. VMهای خصوصی باید از Kerio NAT بگیرند. CIDR واقعی subnet، رنج VPN، DNS و IPهای عمومی هنوز مقدار قطعی ندارند؛ این مخزن عمداً netplan و route سرورها را تغییر نمی‌دهد. قابلیت forwarding و محدودیت anti-spoofing/port-security شبکه ابری را با آروان تطبیق دهید.

Kerio را با VPN برای ۱۰ اتصال هم‌زمان، route شبکه داخلی و NAT خروجی تنظیم کنید. IP سرورهای DNS قابل‌دسترسی را در Ubuntu قرار دهید؛ DNS میزبان‌ها تا نصب Cilium حفظ می‌شود. بعد از VPN باید IP خصوصی تمام ماشین‌های مجاز قابل‌دسترسی باشد. برای Linux یک کاربر `devops` با کلید SSH و sudo بدون رمز لازم است. fingerprint میزبان‌ها را از کنسول آروان بررسی و در known_hosts ثبت کنید؛ host key checking غیرفعال نمی‌شود. دانلود GitHub، Helm، رجیستری کانتینر و مخازن apt باید از VMها ممکن باشد.

قواعد زیر را بر اساس مبدأ مقصد تنظیم کنید؛ هیچ‌یک از پورت‌های مدیریتی زیر نباید به اینترنت باز شوند:

| مبدأ | مقصد | دسترسی |
|---|---|---|
| اینترنت | HAProxy عمومی | TCP 443؛ TCP 80 برای redirect اختیاری |
| اینترنت | Kerio عمومی | پورت VPN مطابق تنظیم واقعی Kerio؛ پنل مدیریت فقط از مبدأ مجاز |
| VPN / monitoring01 | Linuxها | TCP 22 |
| monitoring01 / نودها | master .10 | TCP 6443 |
| چهار نود Kubernetes | یکدیگر | TCP 4240، UDP 8472 برای VXLAN، ICMP؛ kubelet TCP 10250؛ ارتباطات لازم داخلی کلاستر |
| master | خودش | etcd TCP 2379/2380؛ عمومی نشود |
| HAProxy .5 | سه Worker | TCP 30080 |
| سه Worker | NFS .24 | TCP 2049، NFSv4 |
| Velero از نودها / NFS / مدیریت | MinIO .28 | TCP 9000؛ کنسول 9001 فقط VPN/مدیریت |
| monitoring01 .30 | Worker01 .21 | TCP 30900 برای Prometheus |
| monitoring01 .30 | Linuxها | TCP 10050 برای Zabbix passive agent |
| VPN | monitoring01 .30 | TCP 3000 Grafana و 8080 Zabbix |
| سه Worker / monitoring01 | ClickHouse .42 | TCP 8123/9000، در صورت نیاز برنامه |
| سه Worker / monitoring01 | Meilisearch .43 | TCP 7700، با کلید برنامه |
| برنامه‌های مجاز | SQL .40 | TCP 1433 طبق تنظیم دستی SQL |

سیاست کلاستر می‌تواند ارتباط Podها را محدود کند؛ برای DNS، API، دیتابیس و S3 باید اجازه صریح باقی بماند. NodePort ممکن است از همه NICهای نود قابل‌دسترسی باشد؛ محدودیت مبدأ 30080 و 30900 را در فایروال آروان اعمال کنید. سرویس‌ها، Pod CIDR `10.244.0.0/16` و Service CIDR `10.96.0.0/16` نباید با LAN/VPN هم‌پوشانی داشته باشند. MTU Cilium خودکار است؛ تست عبور بسته‌های بزرگ روی شبکه آروان لازم است.

## 2. Management Host Preparation

روی monitoring01 با کاربر devops:

```bash
git clone https://github.com/abdollahian61/evinfl.git
cd evinfl
bash scripts/bootstrap-controller.sh
editor private/site.env
cp ansible/vars/secrets.yml.example private/secrets.yml
chmod 600 private/secrets.yml
editor private/secrets.yml
source private/site.env
```

در `site.env` کاربر و مسیر کلید SSH را واقعی کنید. ابزارهای kubectl/Helm در `.tools/bin` و Ansible/Kubespray در مسیرهای تعریف‌شده نصب می‌شوند؛ نسخه‌ها در `config/versions.env` ثابت‌اند. به‌روزرسانی نسخه‌ها باید همراه بررسی سازگاری انجام شود. برای رمزها حداقل ۳۲ کاراکتر تصادفی از حروف، اعداد، `_` و `-` انتخاب کنید؛ مقدارهای CHANGE_ME پذیرفته نمی‌شوند. فایل لایسنس واقعی MinIO و PEM شامل fullchain سپس private key را در `private/` بگذارید. PEM: `private/haproxy.pem`؛ مسیر license را در secrets مشخص کنید. این فایل‌ها وارد Git نمی‌شوند. نسخه جدا و امن از رمز repository Restic نگه دارید.

تمام دستورهای بعد از ریشه همین مخزن اجرا می‌شوند. از فایل‌های private بکاپ امن بگیرید. Ansible Vault اختیاری است و با `--ask-vault-pass` قابل استفاده است.

## 3. Storage and Per-VM Playbooks

این Roleها برای نصب تازه طراحی شده‌اند. قبل از هر اجرا از کنسول و `lsblk -f` بررسی کنید `/dev/sdb` همان دیسک دوم خالی است. مسیر در `vms/NAME/vars.yml` قابل تغییر است. فرمت خودکار پیش‌فرض خاموش است؛ تنها برای دیسک واقعاً خالی `-e data_disk_allow_format=true` بدهید. دیسک OS، پارتیشن‌دار، filesystem متفاوت یا داده موجود در مقصد bind mount رد می‌شود. مهاجرت داده موجود در این نسخه خودکار نیست. نصب بسته‌ها به‌تنهایی disk partition ایجاد نمی‌کند؛ کل sdb فرمت می‌شود.

```bash
bash vms/monitoring01/install.sh -e data_disk_allow_format=true
bash vms/nfs01/install.sh -e data_disk_allow_format=true
bash vms/minio01/install.sh -e data_disk_allow_format=true
bash vms/clickhouse01/install.sh -e data_disk_allow_format=true
bash vms/meilisearch01/install.sh -e data_disk_allow_format=true
bash vms/k8s-master01/install.sh
bash vms/k8s-worker01/install.sh -e data_disk_allow_format=true
bash vms/k8s-worker02/install.sh -e data_disk_allow_format=true
bash vms/k8s-worker03/install.sh -e data_disk_allow_format=true
bash vms/haproxy01/install.sh -e data_disk_allow_format=true
```

برنامه monitoring01 PostgreSQL/Grafana را روی دیسک دوم با bind mount مستقر می‌کند؛ اجرای Controller روی همان VM مشکلی ندارد. نصب HAProxy به PEM معتبر نیاز دارد. صرفاً برای آزمایش می‌توانید `-e haproxy_allow_self_signed=true` بدهید؛ گواهی ۳۰روزه جایگزین گواهی عملیاتی نیست. دیسک دوم HAProxy برای log در `/srv/haproxy/logs` انتخاب شده است.

برای اجراهای بعدی فلگ فرمت را حذف کنید. هر wrapper به Playbook هم‌نام می‌رود؛ نمونه مستقیم:

```bash
source private/site.env
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
"$VENV_DIR/bin/ansible-playbook" -i ansible/inventory.ini \
  -u "$SSH_USER" --private-key "$SSH_KEY" -b \
  vms/nfs01/install.yml -e @private/secrets.yml
```

`ansible/site.yml` هر ده ماشین Linux را نصب می‌کند، ولی برای اولین اجرا روش مرحله‌ای بالا مناسب‌تر است. نقش base نام میزبان، ساعت، hosts و بسته‌های پایه را تنظیم می‌کند؛ نقش برنامه unit و config سرویس را ایجاد می‌کند. منابع CPU/RAM در vars برای مستندسازی‌اند و VM ابری را ایجاد یا resize نمی‌کنند.

## 4. MinIO and Backup Access

AIStor تجاری تک‌نود با آخرین binary پایدار و checksum رسمی در اولین نصب نصب می‌شود؛ اجرای دوباره آن را خودکار ارتقا نمی‌دهد. نسخه نصب‌شده در سرور ثبت می‌شود. لایسنس را باید خودتان از MinIO تهیه و فایل معتبر بدهید؛ خرید یا صدور لایسنس در این پروژه انجام نشده است. داده‌ها `/srv/minio/data` و endpoint خصوصی `http://192.168.1.28:9000` است؛ Console از VPN روی `http://192.168.1.28:9001` باز می‌شود. استفاده از HTTP داخلی در این تنظیم فعلی رمزنگاری انتقال S3 ندارد؛ برای داده حساس می‌توان بعداً TLS داخلی و trust chain را یکپارچه فعال کرد.

در Console با حساب root تعریف‌شده وارد شوید، bucketهای `velero` و `nfs-backup` را بسازید. برای هر مصرف‌کننده یک کاربر/Access Key جدا بسازید و policy متناظر از `config/minio/` بدهید. این policyها فقط bucket مربوط را مجاز می‌کنند. کلید root را به Velero یا Restic ندهید. برای bucket Restic **lifecycle حذف بر اساس عمر object فعال نکنید**؛ نگهداری فقط با `restic forget/prune` مدیریت می‌شود. برای Velero هم حذف توسط خود Velero انجام شود. Object Lock در این طرح فعال نشده است.

فایل `private/velero-credentials` را با مجوز 600 بسازید:

```ini
[default]
aws_access_key_id = REPLACE_WITH_VELERO_KEY
aws_secret_access_key = REPLACE_WITH_VELERO_SECRET
```

کلید NFS و رمز repository را در `private/secrets.yml` تنظیم کنید. ابتدا ظرفیت واقعی بکاپ را بسنجید؛ ۱۰۰GB ممکن است برای NFS پر و تاریخچه ۱۴روزه کافی نباشد.

## 5. Kubernetes with Kubespray and Cilium

برای ترتیب جدید و مستقل «اول کلاستر بدون CNI، سپس نصب Helm، سپس Cilium»، [راهنمای مینیمال](kubespray-then-cilium.md) را دنبال کنید. این بخش مسیر قبلی با bootstrap کامل و CSR approver فعال را مستند می‌کند. اگر از Inventory مینیمال استفاده کردید، پیش از Metrics Server، تأیید معتبر kubelet serving CSRها یا نصب approver لازم است.

فایل ورودی نصب [cluster.yaml](../cluster.yaml) در ریشه پروژه است و Playbook رسمی Kubespray را import می‌کند. بعد از bootstrap و آماده‌سازی چهار VM، برای اجرای مستقیم از ریشه مخزن:

```bash
source private/site.env
export KUBESPRAY_DIR
export ANSIBLE_CONFIG="$KUBESPRAY_DIR/ansible.cfg"
export ANSIBLE_ROLES_PATH="$KUBESPRAY_DIR/roles"
export ANSIBLE_LIBRARY="$KUBESPRAY_DIR/library"
"$VENV_DIR/bin/ansible-playbook" -i inventory/hosts.ini \
  -u "$SSH_USER" --private-key "$SSH_KEY" -b cluster.yaml
```

اجرای مستقیم بالا خود کلاستر را نصب می‌کند. برای ذخیره kubeconfig موردنیاز مرحله Cilium، پس از موفقیت نصب:

```bash
umask 077
ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" \
  'sudo -n cat /etc/kubernetes/admin.conf' > private/admin.conf
export KUBECONFIG="$PWD/private/admin.conf"
cluster_name=$( .tools/bin/kubectl config view --minify -o jsonpath='{.clusters[0].name}' )
.tools/bin/kubectl config set-cluster "$cluster_name" --server="https://$MASTER_IP:6443"
```

اسکریپت زیر همین `cluster.yaml` را اجرا و kubeconfig را هم دریافت می‌کند؛ یکی از این دو روش نصب را انتخاب کنید:

```bash
bash scripts/install-kubernetes.sh
```

چهار نود از `inventory/hosts.ini` خوانده می‌شوند. تنظیم `kube_network_plugin: cni` فقط زیرساخت CNI را آماده می‌کند، `kube_proxy_remove: true` جلوی kube-proxy را می‌گیرد. تا قبل از Cilium نودها NotReady و CoreDNS Pending طبیعی‌اند. API روی `192.168.1.10:6443` است؛ HAProxy وب به عنوان API Load Balancer استفاده نمی‌شود. kubeconfig خصوصی در `private/admin.conf` ذخیره می‌شود. DNS میزبان‌ها دست‌نخورده می‌ماند تا bootstrap به CNI وابسته نشود.

```bash
bash scripts/install-addons.sh cilium
export KUBECONFIG="$PWD/private/admin.conf"
export PATH="$PWD/.tools/bin:$PATH"
kubectl get nodes -o wide
kubectl -n kube-system get pods
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
```

Cilium با Helm، VXLAN، IPAM مبتنی بر Node PodCIDR، masquerade و kube-proxy replacement نصب می‌شود. Cilium Gateway خاموش است چون کنترلر Gateway این طرح Traefik است. Hubble Relay/UI خصوصی فعال‌اند؛ دسترسی از طریق port-forward با kubeconfig مدیریتی است. Workerها containerd و kubelet را روی sdb نگه می‌دارند؛ mount failure باید سرویس‌های وابسته را متوقف کند.

## 6. NFS and Persistent Volumes

```bash
bash scripts/install-addons.sh storage
kubectl get storageclass
kubectl -n storage-test get pvc,pods,jobs
kubectl -n storage-test logs job/nfs-smoke
```

درایور `nfs.csi.k8s.io` و StorageClass پیش‌فرض `nfs-client`، زیرپوشه مجزا برای PVC می‌سازند. export فقط IP سه Worker را با NFSv4 و root_squash قبول می‌کند؛ روی master workload/PVC اجرا نکنید. حذف PVC با reclaimPolicy=Retain داده را حذف نمی‌کند؛ آزادسازی PV و پوشه قدیمی دستی است. export برای سازگاری با UIDهای متفاوت برنامه‌ها پوشه‌های قابل‌نوشتن دارد؛ NFS مرز امنیتی جداگانه بین مستأجرهای نامطمئن نیست.

## 7. Gateway API, Traefik, and HAProxy

در `manifests/gateway-demo.yaml` دامنه `app.example.com` را واقعی کنید و DNS دامنه را به IP عمومی HAProxy بدهید. مقدار APP_DOMAIN در site.env به‌تنهایی manifest را بازنویسی نمی‌کند. سپس:

```bash
bash scripts/install-addons.sh gateway
kubectl -n traefik get gateway
kubectl -n demo get httproute,pods,service
curl -H 'Host: app.example.com' http://192.168.1.21:30080/
```

تست curl مستقیم Worker از monitoring فقط با مجوز موقت فایروال انجام شود و بعد حذف شود؛ مبدأ عملیاتی 30080 فقط HAProxy است. Gateway/HTTPRoute باید Accepted و ResolvedRefs شوند. HAProxy سه Worker را health check می‌کند؛ TLS در آن خاتمه می‌یابد و Host/X-Forwarded-Proto=https به Traefik می‌رسد. Traefik فقط `.5/32` را برای forwarded headers مورد اعتماد می‌داند. برای بررسی مسیر کامل:

```bash
curl --resolve app.example.com:443:PUBLIC_HAPROXY_IP https://app.example.com/
```

پاسخ باید اطلاعات Pod دموی whoami باشد. `PUBLIC_HAPROXY_IP` را جایگزین کنید. گواهی باید برای دامنه معتبر باشد؛ در حالت تست self-signed فقط آزمایش را با `-k` انجام دهید. برای برنامه واقعی Service از نوع ClusterIP و HTTPRoute به همان Gateway بسازید؛ namespace باید label `gateway-access=enabled` داشته باشد. پس از تست، namespace دموی `demo` را می‌توانید حذف کنید.

## 8. Metrics Server and Prometheus

```bash
bash scripts/install-addons.sh metrics
bash scripts/install-addons.sh monitoring
kubectl top nodes
kubectl top pods -A
kubectl -n monitoring get prometheus,alertmanager,pvc,pods
```

Kubespray برای kubelet serving certificate، CSR rotation و approver را فعال می‌کند؛ Metrics Server با اعتبارسنجی TLS کار می‌کند. اگر آماده نشد `kubectl get csr` و SAN/وضعیت approver را بررسی کنید؛ insecure TLS راه‌حل پیش‌فرض نیست.

Prometheus محلی روی NFS پشتیبانی نمی‌شود؛ به همین دلیل دو Local PV روی sdb Worker01 ساخته می‌شود: Prometheus 10GiB با retention هفت‌روز و سقف 6GB، Alertmanager 2GiB. این فضا با containerd/kubelet روی دیسک ۵۰GB مشترک است و اندازه PV quota filesystem نیست. فضای خالی و DiskPressure را پایش کنید. خرابی Worker01 متریک‌ها را قطع می‌کند؛ این طراحی برای یک replica است. local PVها تحت بکاپ NFS قرار نمی‌گیرند. Grafana بیرونی به `http://192.168.1.21:30900` متصل است و این NodePort فقط از monitoring01 مجاز باشد. مانیتورهای etcd، scheduler، controller-manager و kube-proxy که endpoint قابل‌scrape ندارند غیرفعال‌اند؛ پوشش پایه شامل node-exporter، kubelet، kube-state-metrics و API است.

## 9. Zabbix, Grafana, and Operations

روی VPN:

- Zabbix: `http://192.168.1.30:8080`؛ ورود اولیه بسته رسمی `Admin` / `zabbix` است. فوراً رمز را تغییر دهید.
- Grafana: `http://192.168.1.30:3000`؛ admin و رمز private/secrets.yml. تغییر مقدار فایل بعد از ایجاد دیتابیس رمز قبلی را خودکار rotate نمی‌کند.
- Prometheus datasource در Grafana provision می‌شود. پلاگین Zabbix نصب شده؛ در Grafana آن را فعال و datasource با URL `http://192.168.1.30:8080/api_jsonrpc.php` و حساب/توکن فقط‌خواندنی Zabbix بسازید.

برای نصب agentها:

```bash
source private/site.env
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
"$VENV_DIR/bin/ansible-playbook" -i ansible/inventory.ini -u "$SSH_USER" \
  --private-key "$SSH_KEY" -b ansible/playbooks/agents.yml
```

در Zabbix برای هر Linux یک Host با نام دقیق inventory و IP خصوصی بسازید و template `Linux by Zabbix agent` بدهید. این Role agent passive نصب می‌کند؛ ثبت host/template را خودکار انجام نمی‌دهد. فقط `.30` به TCP10050 دسترسی داشته باشد؛ PSK در این نسخه تنظیم نشده است. برای Windows، agent2 و دسترسی SQL متناسب با تنظیم خودتان را دستی اضافه کنید. برای Kerio از template/SNMP در صورت پشتیبانی همان نسخه استفاده کنید. templateهای HTTP/TCP برای سلامت MinIO، ClickHouse و Meilisearch و فضای دیسک/وضعیت بکاپ اضافه کنید. هیچ Runner روی monitoring نصب نمی‌شود.

## 10. Velero and NFS Backup

```bash
bash scripts/install-addons.sh velero
kubectl -n velero get backupstoragelocations,schedules
bash vms/nfs01/install.sh -e nfs_backup_enabled=true -e nfs_backup_initialize=true
```

دستور دوم NFS را دوباره نصب نمی‌کند، تنظیمات را همگرا و repository جدید را در صورت نیاز init می‌کند؛ هر خطای probe باید بررسی شود و init روی bucket با repository ناشناخته انجام نشود. اجرای بعدی فقط `-e nfs_backup_enabled=true` لازم دارد. Cron روی NFS ساعت 02:00 Asia/Tehran اجرا می‌شود. از نصب هم‌زمان cron نمونه قبلی و cron Ansible خودداری کنید. Velero ساعت 22:00 UTC اجرا می‌شود؛ ساعت Velero و cron محلی متفاوت است و تراکنش مشترک ایجاد نمی‌کند. نگهداری هر دو ۱۴ روز است.

Velero فقط منابع Kubernetes را می‌گیرد؛ node-agent و volume snapshot خاموش‌اند. فایل تمام share، شامل PVCها، با Restic از `/srv/nfs/kubernetes` بکاپ می‌شود. این دو، بکاپ آنلاین application-consistent دیتابیس نیستند؛ برای برنامه دارای state قبل از بکاپ نوشتن را متوقف یا hook مناسب اجرا کنید. دیتابیس‌های مستقل SQL/ClickHouse/Meilisearch در دامنه فعلی بکاپ خودکار نیستند.

آزمون دستی روی NFS:

```bash
sudo /usr/local/sbin/nfs-to-minio.sh backup
sudo /usr/local/sbin/nfs-to-minio.sh snapshots
sudo /usr/local/sbin/nfs-to-minio.sh check
```

برای گرفتن فوری منابع بدون CLI جداگانه Velero:

```bash
kubectl -n velero create -f - <<'YAML'
apiVersion: velero.io/v1
kind: Backup
metadata:
  generateName: manual-resources-
  namespace: velero
spec:
  includedNamespaces: ['*']
  includeClusterResources: true
  snapshotVolumes: false
  defaultVolumesToFsBackup: false
  ttl: 336h0m0s
  storageLocation: default
YAML
kubectl -n velero get backups
```

وضعیت باید Completed باشد؛ PartiallyFailed نیازمند بررسی log است. در [راهنمای NFS](nfs-backup.md) مراحل restore به مسیر موقت آمده است. بازیابی کامل: ابتدا زیرساخت و NFS سالم، سپس بازیابی فایل‌ها به مسیر موقت، کنترل مسیرهای PVC/PV و مالکیت، توقف نوشتن برنامه‌ها، انتقال کنترل‌شده فایل‌ها به share، restore منابع Velero و بررسی PVهای Retain/hostname محلی. در کلاستر مقصد تازه، ابزارهای زیرساختی را از Git نصب کنید و restore منابع را با namespace برنامه انتخاب کنید تا CRD/operatorهای تازه با نسخه قدیمی جایگزین نشوند. نمونه Restore را با نام backup واقعی اجرا کنید:

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: app-restore-test
  namespace: velero
spec:
  backupName: REPLACE_WITH_COMPLETED_BACKUP
  includedNamespaces: [demo]
  restorePVs: false
```

این دستور فایل volume را برنمی‌گرداند. آزمون restore در namespace/محیط جدا و تطبیق یک فایل آزمایشی با hash، شرط پذیرش بکاپ است. رمز Restic و کلیدهای S3 باید خارج از همین MinIO نیز محفوظ باشند. MinIO تک‌نود و یک دیسک، کپی مستقل خارج از این زیرساخت نیست.

## 11. Data Services and Health Validation

ClickHouse روی .42، مسیر `/var/lib/clickhouse` و user برنامه با رمز hash‌شده برای سه Worker و monitoring مجاز است؛ default فقط loopback. Meilisearch روی .43:7700 در production و master key حداقل ۳۲ کاراکتری نصب می‌شود. master key را به frontend ندهید؛ کلید محدود برنامه ایجاد کنید. SQL 2019 Standard روی Windows 2025 طبق تصمیم شما دستی است؛ این مخزن نصب یا تغییر SQL را انجام نمی‌دهد. Playbookهای verify برای Kerio/SQL فقط اتصال TCP را بررسی می‌کنند و سلامت کامل محصول را اثبات نمی‌کنند.

```bash
curl http://192.168.1.43:7700/health
curl http://192.168.1.42:8123/ping
ssh devops@192.168.1.28 'sudo systemctl status minio --no-pager'
ssh devops@192.168.1.24 'sudo exportfs -v; findmnt /srv/nfs'
```

دسترسی منفی NFS از monitoring و مثبت از Worker را نیز بررسی کنید. روی VMهای خصوصی `ip route`, `resolvectl status` و خروج HTTPS به یک registry مجاز را بررسی کنید. از بیرون فقط HTTPS و VPN باید طبق سیاست دسترس‌پذیر باشند.

## 12. Control Plane Maintenance and Recovery

این کلاستر یک master دارد؛ خرابی آن API/etcd را از دسترس خارج می‌کند. Velero جای snapshot etcd و کلیدهای control plane را نمی‌گیرد. Kubespray قبل از upgrade برای etcd backup می‌سازد؛ زمان‌بندی مستقل snapshot و نگهداری رمزنگاری‌شده certها/kubeconfigها باید جدا از MinIO تک‌نود طراحی شود. روش رسمی [بکاپ و بازیابی etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) را برای همین نسخه دنبال کنید و restore را روی ماشین آزمایشی انجام دهید. این مخزن cron خودکار etcd را نصب نمی‌کند؛ فعلاً scope اجرایی بکاپ منابع Velero و فایل NFS است.

قبل از هر upgrade: نسخه‌های pinned را مقایسه، snapshot/بکاپ قابل‌بازیابی تهیه، release notes را مطالعه و ابتدا در محیط آزمایشی نصب کنید. ارتقای binary MinIO، schema Zabbix و نسخه Meilisearch نیازمند برنامه جداست؛ نصب مجدد Playbook معادل برنامه upgrade تضمین‌شده نیست.

## Validation and References

`scripts/validate.py` syntax Bash/YAML، انسجام نسخه‌ها و Playbookها را بررسی می‌کند. شش chart pinned با Helm template رندر شده‌اند. این آزمون‌ها جای اتصال به VM، تست شبکه آروان یا restore واقعی را نمی‌گیرند. pipeline GitLab فقط validation انجام می‌دهد و چیزی deploy نمی‌کند.

- [Kubespray v2.32.0](https://github.com/kubernetes-sigs/kubespray/releases/tag/v2.32.0)
- [Cilium بدون kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
- [Traefik chart](https://github.com/traefik/traefik-helm-chart)
- [Prometheus storage و محدودیت NFS](https://prometheus.io/docs/prometheus/latest/storage/)
- [Velero AWS plugin compatibility](https://github.com/velero-io/velero-plugin-for-aws)
- [MinIO AIStor Ubuntu](https://docs.min.io/aistor/installation/linux/install/deploy-aistor-on-ubuntu-server/)
- [Grafana Debian/Ubuntu](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/)

طرح Visio قابل‌ویرایش پس از اعلام «final» تهیه می‌شود.

The `cluster.yaml` entry point uses Ansible's official [import_playbook](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/import_playbook_module.html) mechanism.
