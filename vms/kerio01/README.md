# kerio01

Kerio Control: installation/configuration owned by the project owner. Configure the public interface, private address, client VPN for 10 users, routes and outbound NAT.

IP `192.168.1.4`, 4 vCPU, RAM 8 GB, OS disk 30 GB.

`verify.yml` checks private TCP reachability from the controller. It does not install the operating system or the product. Kerio and MSSQL remain manually installed, per the owner's instruction.

```bash
ansible-playbook -i ansible/inventory.ini vms/kerio01/verify.yml
```

Port 4090 must match the actual product configuration.
