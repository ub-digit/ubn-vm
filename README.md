# ubn-vm

Detta är en virtuell utvecklingsmiljö för __UBNext__.
Allt som *__ska__* behövas för att få igång den är att köra skripten nedan under
rubriken __Skriptade steg__.
Om man stöter på problem kan man behöva köra kommandona stegvis var för sig.
Se i så fall under rubriken __Manuella steg__.


## Skriptade steg

- I normalfallet är allt som behövs att köra __preprovision-skriptet__ och
sedan __vagrant up___:
```bash
bin/preprovision
vagrant up
```

## Manuella steg
- Sätt miljön med hjälp av skript som skapar en mjuk länk:
```bash
bin/set-stage.sh devel
mkdir stages.config om den inte redan finns.
```

- Generera konfig-variabler för vald miljö:
```bash
ansible-playbook -i "localhost," -c local pre-provisioning/playbook.yml
```

- Kicka igång virtuella maskinen:
```bash
vagrant up
```

- Om det behövs, t.ex. om det kraschar under ```vagrant up``` kan man behöva
köra ```provision``` igen:
```bash
vagrant provision
```
