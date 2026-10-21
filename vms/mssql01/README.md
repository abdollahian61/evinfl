# mssql01

Windows Server 2025 + SQL Server 2019 Standard, data disk 500 GB. Installation owned by the project owner.

IP `192.168.1.40`, 8 vCPU, RAM 16 GB, OS disk 100 GB.

`verify.yml` checks private TCP reachability from the controller. It does not install the operating system or the product. Kerio and MSSQL remain manually installed, per the owner's instruction.

```bash
ansible-playbook -i ansible/inventory.ini vms/mssql01/verify.yml
```

Port 1433 must match the actual product configuration.
