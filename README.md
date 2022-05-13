
# Warning: unfinished work in progress

# Postgres backups with pg_dump in Kubernetes

Clone the repository from https://github.com/viorel-anghel/pgdump-kubernetes.git

If you just want to use the tool, skip to the section "Using the Helm chart". If you want to understand how this has been created, just read along.

## The pgdump.sh script

## The Docker image

## Preparing the Kubernetes test environment

## Kubernetes basic yamls

## Creating the Helm chart

## Using the Helm chart


```
cd helm
helm install --upgrade -f values.yaml -f values_override.yaml -n <NAMESPACE> <RELEASE-NAME> . 
```

We recommend you use a release name like <SOMETHING>-pgdump. All the resources created by the helm chart will have this name: a PVC, a deployment and a cronjob.

Make sure you have the correct values, especially for 
- `pghost` - this should be the name of the service (svc) pointing to the postgres database and
- `secret_pgpass` - this should be †he name of the secret holding the postgres password.


