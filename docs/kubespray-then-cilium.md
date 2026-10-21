# نصب مرحله‌ای: Kubespray ← Helm ← Cilium

این مسیر مخصوص نصب تازه همین کلاستر است: یک Master و سه Worker روی Ubuntu 24.04. ابتدا فقط Kubernetes/containerd/etcd و منابع CoreDNS نصب می‌شوند؛ سپس Helm روی VM مدیریت و بعد Cilium با Helm. Traefik، NFS، مانیتورینگ و بکاپ در این مرحله نصب نمی‌شوند. این راهنما را از `monitoring01` با کاربر `devops` اجرا کنید، نه از هر چهار نود.

| نقش | نام | IP خصوصی |
|---|---|---|
| Master + etcd | k8s-master01 | 192.168.1.10 |
| Worker | k8s-worker01 | 192.168.1.21 |
| Worker | k8s-worker02 | 192.168.1.22 |
| Worker | k8s-worker03 | 192.168.1.23 |

نسخه ثابت این راهنما: Kubespray `v2.32.0`، Kubernetes `1.36.4`، Helm `3.22.0` و Cilium chart `1.20.3`. نسخه‌ها در [versions.env](../config/versions.env) هستند؛ برای اجرای قابل‌تکرار از `latest` استفاده نمی‌کنیم. Cilium 1.20 در مستندات رسمی Kubernetes 1.36 را پوشش می‌دهد.

## ۱. دسترسی و آماده‌سازی

- روی چهار VM، Ubuntu 24.04 تازه با hostname یکتا و IP ثابت خصوصی لازم است. کاربر SSH باید کلید معتبر و `sudo` بدون رمز داشته باشد. fingerprint میزبان‌ها را از کنسول بررسی و هنگام اتصال SSH ثبت کنید.
- این VMها نباید از قبل عضو RKE2، K3s یا کلاستر دیگری باشند. اجرای این راهنما روی نود نصب‌شده، روش مهاجرت یا تغییر CNI نیست.
- همه نودها باید از Kerio به اینترنت، registryها و مخازن بسته دسترسی داشته باشند و DNS میزبان قبل از نصب کار کند. ساعت‌ها همگام باشند؛ کرنل استاندارد Ubuntu 24.04 برای این baseline مناسب است.
- Pod CIDR برابر `10.244.0.0/16` و Service CIDR برابر `10.96.0.0/16` است؛ قبل از نصب عدم هم‌پوشانی با LAN و VPN را تأیید کنید. subnet mask شبکه VMها از روی این IPها فرض نشده است.

در فایروال آروان/میزبان، دسترسی‌های خصوصی زیر لازم‌اند؛ هیچ پورت مدیریتی به اینترنت باز نشود:

| ارتباط | پورت |
|---|---|
| مدیریت/VPN به نودها | TCP 22 |
| مدیریت و چهار نود به Master | TCP 6443 |
| Master به kubelet نودها | TCP 10250 |
| etcd روی Master | TCP 2379/2380 در محدوده لازم داخلی؛ بدون دسترسی عمومی |
| چهار نود به یکدیگر، VXLAN | UDP 8472 |
| چهار نود به یکدیگر، health | TCP 4240 و ICMP |
| نودهای کلاستر برای Hubble | TCP 4244 |
| خروج نودها | DNS تنظیم‌شده، NTP و HTTPS به مخازن/registryها از Kerio |

این فقط ماتریس ارتباط زیرساختی است؛ دسترسی Podها و Serviceها طبق سیاست داخلی کلاستر نیز باید برقرار باشد. فعلاً NodePort عمومی باز نمی‌کنیم. route، NIC، port security آروان و netplan توسط این فایل‌ها عوض نمی‌شوند. اگر UFW فعال است، قواعد forwarding/ترافیک Pod و نودها را هم بررسی کنید؛ حذف کورکورانه قوانین فایروال توصیه نمی‌شود.

روی ماشین مدیریت:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/abdollahian61/evinfl.git
cd evinfl
bash scripts/bootstrap-controller.sh --ansible-only
editor private/site.env
source private/site.env
export KUBESPRAY_DIR
export PATH="$VENV_DIR/bin:$PWD/.tools/bin:$PATH"
export ANSIBLE_CONFIG="$KUBESPRAY_DIR/ansible.cfg"
export ANSIBLE_ROLES_PATH="$KUBESPRAY_DIR/roles"
export ANSIBLE_LIBRARY="$KUBESPRAY_DIR/library"
export ANSIBLE_HOST_KEY_CHECKING=True
export ANSIBLE_SSH_ARGS='-o ControlMaster=auto -o ControlPersist=60s -o ConnectionAttempts=10'
```

اگر repo را قبلاً دارید، به پوشه همان checkout بروید و پس از بررسی تغییرات محلی `git pull --ff-only` کنید؛ دوباره clone لازم نیست. در `site.env` مقدار `SSH_USER` و مسیر `SSH_KEY` را واقعی کنید. حالت `--ansible-only` فقط پیش‌نیازهای Controller، Ansible و Kubespray ثابت را نصب می‌کند؛ Helm و kubectl را در این مرحله نصب نمی‌کند. این مسیر به secrets سرویس‌های MinIO و دیتابیس نیاز ندارد. با باز کردن ترمینال جدید، source و exportهای بالا را دوباره اجرا کنید.

اگر می‌خواهید دیسک دوم ۵۰GB Workerها برای containerd/kubelet استفاده شود، پیش از نصب کلاستر، [Playbookهای آماده‌سازی چهار VM](../vms/README.md) را اجرا کنید. ابتدا `lsblk -f` و خالی بودن `/dev/sdb` را بررسی کنید. برای دیسک خالی، Role فقط با فلگ صریح `-e data_disk_allow_format=true` فرمت می‌کند. اگر این آماده‌سازی را انجام ندهید، Kubespray از مسیر استاندارد `/var/lib/containerd` و دیسک OS استفاده می‌کند؛ خودبه‌خود sdb را به آن منتقل نمی‌کند.

## ۲. Inventory ساده

فقط [inventory/minimal/hosts.ini](../inventory/minimal/hosts.ini) را ویرایش کنید. همین فایل برای یک Master و سه Worker آماده است:

```ini
[kube_control_plane]
k8s-master01 ansible_host=192.168.1.10 ip=192.168.1.10 access_ip=192.168.1.10

[etcd]
k8s-master01

[kube_node]
k8s-worker01 ansible_host=192.168.1.21 ip=192.168.1.21 access_ip=192.168.1.21
k8s-worker02 ansible_host=192.168.1.22 ip=192.168.1.22 access_ip=192.168.1.22
k8s-worker03 ansible_host=192.168.1.23 ip=192.168.1.23 access_ip=192.168.1.23

[k8s_cluster:children]
kube_control_plane
kube_node
```

تنظیمات لازم از [group_vars/k8s_cluster.yml](../inventory/minimal/group_vars/k8s_cluster.yml) کنار همین Inventory خودکار خوانده می‌شوند. بخش تعیین‌کننده آن:

```yaml
kube_network_plugin: cni
kube_proxy_remove: true
helm_enabled: false
kubelet_csr_approver_enabled: false
enable_nodelocaldns: false
resolvconf_mode: none
```

`cni` در این نسخه Kubespray فقط binaryهای عمومی CNI را کپی می‌کند و شبکه Pod را راه نمی‌اندازد. `kube_proxy_remove` باعث می‌شود kube-proxy از ابتدا نصب نشود. `helm_enabled: false` و غیرفعال بودن CSR approver جلوی نصب Helm/چارت آن در مرحله اول را می‌گیرند. DNS میزبان حفظ می‌شود تا دانلود imageهای Cilium به شبکه‌ای که هنوز نصب نشده وابسته نباشد. از همین مسیر `inventory/minimal/hosts.ini` استفاده کنید؛ `inventory/hosts.ini` پروفایل قبلی با افزونه‌های بیشتری است.

اگر IP Master را تغییر می‌دهید، علاوه بر Inventory، مقدار `kube_apiserver_bind_address` و `supplementary_addresses_in_ssl_keys` در group_vars و `k8sServiceHost` در values مربوط به Cilium را هم تغییر دهید.

پیش از نصب، اتصال SSH/Python و sudo را کنترل کنید:

```bash
ansible -i inventory/minimal/hosts.ini k8s_cluster \
  -u "$SSH_USER" --private-key "$SSH_KEY" -m ansible.builtin.ping
ansible -i inventory/minimal/hosts.ini k8s_cluster \
  -u "$SSH_USER" --private-key "$SSH_KEY" -b -m ansible.builtin.command -a 'id -u'
```

دستور اول باید برای چهار نود `pong` و دستور دوم عدد `0` بدهد. خطاهای DNS، SSH، sudo یا دانلود را قبل از ادامه رفع کنید.

## ۳. نصب کلاستر با cluster.yaml

فایل [cluster.yaml](../cluster.yaml) در ریشه پروژه، Playbook رسمی همان checkout ثابت Kubespray را import می‌کند. ابتدا بررسی syntax:

```bash
ansible-playbook -i inventory/minimal/hosts.ini \
  -u "$SSH_USER" --private-key "$SSH_KEY" -b \
  cluster.yaml --syntax-check
```

سپس نصب واقعی:

```bash
ansible-playbook -i inventory/minimal/hosts.ini \
  -u "$SSH_USER" --private-key "$SSH_KEY" -b \
  cluster.yaml
```

در پایان `failed=0` و `unreachable=0` برای نودها لازم است. در صورت قطع شدن دانلود، علت را رفع و همان فرمان را دوباره اجرا کنید؛ حذف کلاستر یا reset قدم اول رفع مشکل نیست. پس از موفقیت، خروجی kubectl و kubeconfig در `inventory/minimal/artifacts/` ایجاد می‌شود. معماری Controller و نودها در این روش دریافت kubectl باید یکسان باشد؛ طرح فعلی VMها amd64 است.

```bash
mkdir -p .tools/bin private
chmod 700 private
install -m 755 inventory/minimal/artifacts/kubectl .tools/bin/kubectl
install -m 600 inventory/minimal/artifacts/admin.conf private/admin.conf
export KUBECONFIG="$PWD/private/admin.conf"
kubectl get --raw=/readyz
kubectl get nodes -o wide
kubectl -n kube-system get pods,daemonsets
```

API باید `ok` بدهد. تا قبل از Cilium، `NotReady` بودن نودها و `Pending` بودن CoreDNS طبیعی است؛ static Podهای API/etcd به شبکه Pod وابسته نیستند. نباید DaemonSet مربوط به Calico، Flannel، Cilium یا kube-proxy وجود داشته باشد. فایل‌های artifacts و private را وارد Git نکنید؛ kubeconfig دسترسی مدیریتی دارد. اگر نودها از قبل Ready یا CNI دیگری موجود است، قبل از نصب Cilium منشأ آن را بررسی کنید.

### تأیید اولیه گواهی kubelet

در این پروفایل، گواهی serving kubelet باید با CA کلاستر معتبر باشد و approver خودکار نصب نشده است. پیش از فرمان‌های `exec` و `logs` مراحل بعد، درخواست‌های اولیه چهار نود را بررسی کنید:

```bash
kubectl get csr
kubectl describe csr REPLACE_WITH_CSR_NAME
kubectl get csr REPLACE_WITH_CSR_NAME -o jsonpath='{.spec.request}' \
  | base64 --decode | openssl req -noout -text
```

نام `REPLACE_WITH_CSR_NAME` را با نام واقعی همان درخواست جایگزین کنید. فقط درخواست دارای signer برابر `kubernetes.io/kubelet-serving`، هویت `system:node:NAME` متعلق به یکی از چهار نود خودتان، CN/O سازگار و SAN/IPهای معتبر همان نود را تأیید کنید. برای هر درخواست بررسی‌شده جداگانه:

```bash
kubectl certificate approve REPLACE_WITH_CSR_NAME
kubectl get csr
```

وضعیت باید `Approved,Issued` شود. همه CSRها را یک‌جا approve نکنید؛ اگر درخواست وجود ندارد، وضعیت kubelet/CSR را بررسی کنید. تأیید گواهی باعث Ready شدن شبکه نمی‌شود؛ Ready شدن نودها هنوز به Cilium وابسته است. درخواست‌های تمدید بعدی هم نیازمند بررسی یا یک approver محدود و معتبر هستند.

## ۴. حالا Helm را نصب کنید

فقط روی ماشین مدیریت:

```bash
bash scripts/install-helm.sh
export PATH="$PWD/.tools/bin:$PATH"
helm version --short
helm list -A
```

این اسکریپت binary نسخه ثابت Helm را از منبع رسمی می‌گیرد، checksum را بررسی می‌کند و در `.tools/bin/helm` قرار می‌دهد. Helm کلاینت است؛ روی تک‌تک Workerها یا داخل کلاستر سرویس جداگانه‌ای نصب نمی‌کند. `helm list -A` قبل از نصب Cilium باید اجرا شود حتی اگر هنوز Pod network آماده نیست.

## ۵. تنظیمات Cilium مناسب این معماری

فایل کامل و قابل‌ویرایش: [config/helm/cilium.yaml](../config/helm/cilium.yaml). این یک baseline برای همین کلاستر کوچک روی شبکه خصوصی ابر است؛ بهترین مقدار memory/MTU به بار واقعی و شبکه بستگی دارد.

| تنظیم | مقدار/دلیل |
|---|---|
| kubeProxyReplacement | فعال؛ کلاستر از ابتدا kube-proxy ندارد |
| k8sServiceHost / Port | `192.168.1.10:6443`؛ bootstrap از API مستقیم |
| IPAM | Kubernetes؛ برای هر نود از Pod CIDR تعریف‌شده، subnet اختصاص می‌یابد |
| routing | VXLAN؛ بدون نیاز به route جدا برای Pod CIDR هر نود در آروان |
| MTU | تشخیص خودکار؛ پس از نصب عبور بسته بزرگ باید تست شود |
| masquerade | eBPF؛ سپس خروج اینترنت از gateway موجود Kerio |
| LoadBalancer mode | SNAT؛ بدون نیاز به طراحی مسیر برگشت DSR |
| Operator | دو replica با anti-affinity پیش‌فرض چارت و PDB با maxUnavailable=1 |
| منابع | requests مشخص و سقف حافظه اولیه؛ CPU limit تنظیم نشده است |
| Hubble | Relay و UI فعال، سرویس‌های خصوصی؛ UI با port-forward |
| Gateway/Ingress داخلی Cilium | خاموش؛ بعداً Traefik کنترلر Gateway API خواهد بود |
| imageها | digestهای پیش‌فرض همان چارت ثابت حفظ می‌شوند |

سقف حافظه Agent فعلاً 1GiB و Operator برابر 512MiB است؛ OOM/restart، تعداد endpoint و policyها را پایش و با افزایش بار اصلاح کنید. دو Operator، خرابی تک Master/etcd را جبران نمی‌کنند. VXLAN رمزنگاری نیست؛ WireGuard و host firewall بدون سنجش مسیر، MTU و نیاز عملیاتی در این baseline فعال نشده‌اند. Prometheus ServiceMonitor هم تا زمان نصب CRDهای آن فعال نشده است.

نصب با Helm:

```bash
source config/versions.env
helm repo add cilium https://helm.cilium.io/
helm repo update cilium
helm template cilium cilium/cilium \
  --version "$CILIUM_CHART_VERSION" --namespace kube-system \
  -f config/helm/cilium.yaml > /tmp/evinfl-cilium-rendered.yaml
helm upgrade --install cilium cilium/cilium \
  --version "$CILIUM_CHART_VERSION" --namespace kube-system \
  -f config/helm/cilium.yaml --wait --timeout 15m
```

`helm template` ساختار و templateها را بررسی می‌کند؛ تست شبکه یا admission واقعی نیست. این فرمان نصب برای پروفایل مینیمال است؛ اجرای `install-addons.sh all` ابزارهای مراحل بعد را هم نصب می‌کند و در این مرحله لازم نیست.

## ۶. کنترل Ready شدن

```bash
kubectl -n kube-system rollout status daemonset/cilium --timeout=600s
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=600s
kubectl -n kube-system rollout status deployment/coredns --timeout=300s
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl -n kube-system exec daemonset/cilium -- cilium-dbg status --verbose
kubectl -n kube-system exec daemonset/cilium -- cilium-health status --verbose
```

چهار نود باید Ready و Agent روی هر چهار نود حاضر باشد. دو Operator باید روی دو نود متفاوت اجرا شوند؛ وضعیت kube-proxy replacement باید فعال باشد. این دو فرمان exec وضعیت یک Agent را نشان می‌دهند؛ برای بررسی همه Agentها:

```bash
for pod in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
  kubectl -n kube-system exec "$pod" -- cilium-dbg status --verbose || break
done
```

## ۷. تست واقعی Pod، Service و DNS

```bash
kubectl apply -f manifests/cilium-smoke.yaml
kubectl -n cilium-smoke rollout status daemonset/echo --timeout=300s
kubectl -n cilium-smoke rollout status deployment/client --timeout=300s
kubectl -n cilium-smoke get pods -o wide
kubectl -n cilium-smoke exec deployment/client -- nslookup kubernetes.default.svc.cluster.local
kubectl -n cilium-smoke exec deployment/client -- wget -qO- http://echo:8080/
```

باید سه Pod سرویس echo روی سه Worker و یک client داشته باشید. پاسخ HTTP نام یک Pod است. برای تست مستقیم IP همه سرورها، شامل نودهای دیگر:

```bash
for pod_ip in $(kubectl -n cilium-smoke get pods -l app=cilium-smoke-echo -o jsonpath='{.items[*].status.podIP}'); do
  kubectl -n cilium-smoke exec deployment/client -- wget -T 5 -qO- "http://$pod_ip:8080/" || break
done
```

هر سه IP باید پاسخ بدهند. اگر خروج اینترنت Pod هم لازم است، با wget/curl image مورداعتماد خودتان HTTPS یک مقصد مجاز را تست کنید. BusyBox این smoke test برای تست HTTP داخلی انتخاب شده است؛ وجود CA و قابلیت HTTPS آن معیار مستقل قبولی شبکه نیست. این آزمایش کوچک کارایی/MTU یا تمام NetworkPolicyها را اثبات نمی‌کند؛ برای پذیرش عملیاتی، تست connectivity کامل Cilium و اندازه بسته متناسب با MTU آروان را هم اجرا کنید. namespace تست را بعد از اتمام پاک کنید:

```bash
kubectl delete namespace cilium-smoke
```

Hubble UI از ترمینال دیگری روی Controller:

```bash
kubectl -n kube-system port-forward --address 127.0.0.1 service/hubble-ui 12000:80
```

روی مرورگر همان ماشین به `http://127.0.0.1:12000` بروید؛ اگر Controller ماشین راه دور است، از کامپیوتر خودتان تونل SSH بدهید: `ssh -L 12000:127.0.0.1:12000 devops@192.168.1.30`. UI عمومی یا بدون کنترل دسترسی منتشر نشده است.

## ۸. اگر نصب گیر کرد

```bash
kubectl -n kube-system get pods -o wide
kubectl -n kube-system get events --sort-by=.lastTimestamp
kubectl -n kube-system logs daemonset/cilium --all-containers --tail=100
kubectl -n kube-system logs deployment/cilium-operator --tail=100
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR
```

| نشانه | بررسی اول |
|---|---|
| ImagePullBackOff | DNS و خروج اینترنت همان نود از Kerio، دسترسی registry |
| Agent به API وصل نمی‌شود | `.10:6443`، route، firewall و k8sServiceHost |
| PodCIDR خالی | allocate-node-cidrs و Pod CIDR در controller-manager |
| ارتباط بین نودها خراب است | UDP8472، MTU، فایروال و port security شبکه |
| DNS Pod خراب است | CoreDNS Ready، ClusterIP kube-dns و مسیر Service |
| Operator Pending | ظرفیت و anti-affinity؛ باید دو نود قابل‌زمان‌بندی برای Operator باشند |
| OOMKilled | مصرف واقعی و limit Agent/Operator؛ بعد از اندازه‌گیری values را تغییر دهید |

`helm uninstall cilium` راه رفع عمومی خطا نیست؛ حذف CNI روی ارتباط workloadها اثر مستقیم دارد. تغییر هر بار values را با نسخه ثابت چارت و `helm upgrade` انجام دهید. پس از Cilium، برای upgrade آینده Kubernetes همین Inventory مینیمال و الگوی CNI خارجی را حفظ کنید؛ Kubespray را ناخواسته روی `kube_network_plugin: cilium` تغییر ندهید، چون ownership نصب باید همچنان با Helm بماند.

این پروفایل CSR approver را نصب نکرده است. تأیید اولیه serving CSRها در مرحله ۳ انجام می‌شود؛ برای تمدید بعدی و پیش از Metrics Server، فرایند بررسی CSRها یا approver محدود و معتبر را برقرار نگه دارید. از approve خودکار همه CSRها و `--kubelet-insecure-tls` به عنوان تنظیم دائمی استفاده نکنید. سرویس‌های مراحل بعد و مدیریت CSR در [راهنمای کامل زیرساخت](install-a-to-z.md) توضیح داده شده‌اند؛ تا این مرحله نصب خودکار آن‌ها انجام نشده است.

## منابع و وضعیت بررسی

- [Kubespray v2.32.0](https://github.com/kubernetes-sigs/kubespray/releases/tag/v2.32.0)
- [حالت generic CNI در tag انتخابی](https://github.com/kubernetes-sigs/kubespray/blob/v2.32.0/roles/network_plugin/cni/tasks/main.yml)
- [kube-proxy skip در Kubespray](https://github.com/kubernetes-sigs/kubespray/blob/v2.32.0/roles/kubespray_defaults/defaults/main/main.yml)
- [Cilium Helm installation](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Cilium kube-proxy replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
- [سازگاری Kubernetes](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
- [پیش‌نیازها و پورت‌های Cilium](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [نصب رسمی Helm](https://helm.sh/docs/v3/intro/install/)

بررسی محلی شامل YAML/Bash، بارگذاری Inventory مینیمال، syntax ورودی cluster.yaml با Kubespray ثابت و رندر Cilium است. نصب روی VMهای شما و تست شبکه واقعی اجرا نشده‌اند.
