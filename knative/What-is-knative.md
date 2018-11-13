# Knative


## Resources

https://github.com/knative/docs



export IP_ADDRESS=$(kubectl get node  --output 'jsonpath={.items[0].status.addresses[0].address}'):$(kubectl get svc knative-ingressgateway --namespace istio-system   --output 'jsonpath={.spec.ports[?(@.port==80)].nodePort}')

export HOST_URL=$(kubectl get ksvc helloworld-go  --output jsonpath='{.status.domain}')

curl -H "Host: ${HOST_URL}" http://${IP_ADDRESS}
