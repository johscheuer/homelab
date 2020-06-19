# Vegeta

## Installation

```bash
curl -sLo vegeta.tar.gz https://github.com/tsenart/vegeta/releases/download/cli%2Fv12.1.0/vegeta-12.1.0-linux-amd64.tar.gz
tar xfvz vegeta.tar.gz
sudo mv vegeta /usr/local/bin
rm -f vegeta.tar.gz LICENSE README.md CHANGELOG
```

```bash
echo "GET http://${IP_ADDRESS}/" | vegeta attack --header "Host: ${HOST_URL}" -duration=5s --rate=400 > result.bin
vegeta report result.bin
```
