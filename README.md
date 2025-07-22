run the command to instal the server
```
curl -L https://raw.githubusercontent.com/auszed/n8n_vps/refs/heads/main/n8n_install.sh | sh
```

enable https
```
sh <(curl  -L https://raw.githubusercontent.com/auszed/n8n_vps/refs/heads/main/n8n_ngrok.sh )
```


clone repository
```
git clone https://github.com/auszed/n8n_vps.git
cd n8n_vps
```

executable
```
chmod +x n8n_install.sh
```
run script
```
./n8n_install.sh
```
