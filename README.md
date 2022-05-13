

# Warning: early release, may contain errors.

# Postgres backups with pg_dump - from shell scripting to Kubernetes

Clone the repository from https://github.com/viorel-anghel/pgdump-kubernetes.git 

If you just want to use this, skip to the section "Using the Helm chart". If you want to understand how this has been created, read on.

## The pgdump.sh script

This is a simple shell script based on `pg_dump` which is creating a sql dump for a database. 

A few notes on  how this may be different from other scripts found on the net:
- using `pg_dump` (not `pg_dumpall`) and dumping each db in it's own file, see the `while` loop
- carefully checking for errors
- using environment variables `PGHOST PGPORT PGUSER PGPASSWORD` to simplify psql/pg_dump commands (see https://www.postgresql.org/docs/current/libpq-envars.html) and to be docker/kubernetes ready

## The Docker image

The `Dockerfile` for building the docker image is very simple, basically we start from `bitnami/postgres` image which already has all the postgresql tools, adding the pgdump.sh script. 

Setting a 'do nothing' `ENTRYPOINT` will be usefull in this case because you can start a container or pod from it, exec 'inside' it and test things.

Building and pushing (to docker hub vvang repository) the image steps:
```
docker build -t pgdump:0.5 .
docker tag pgdump:0.5 vvang/pgdump:0.5
docker push vvang/pgdump:0.5
```

## Preparing the Kubernetes test environment

I have tested this on KIND (local cluster) and DigitalOcean managed Kubernetes so I'll just assume you have access with `kubectl` and `helm` to a Kubernetes cluster.

I have created a namespace `pg-helm` and I used helm to install postgres in there:
```
kubectl create ns pg-helm
helm install -n pg-helm --set auth.postgresPassword='p123456' mypg bitnami/postgresql
```

As you can see in the instructions displayed by the helm command, you can access the postgres server using the service `mypg-postgresql` (`mypg-postgresql.pg-helm` from other namespaces), with user postgres and the password stored in the secret `mypg-postgresql`:

```
kubectl -n pg-helm get services
kubectl -n pg-helm get secrets
kubectl get secret --namespace pg-helm mypg-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d
```

If you uninstall the helm chart, the PVC won't be deleted, as a safety for you. If you re-install it, the old PVC and postgres data will be used. 

## Kubernetes basic yamls
I have decided to use dedicated volumes for dumps so first we'll need to create a PVC, see the file `pvc.yml`. 

Then, we'll create a deployment (a simple pod will suffice) which can be used to test the dump script or to do restores. Looking at the file `deployment.yml`:
- all the objects I'm creating (pvc, deployment, cronjob) will have the same name, in this case `mypg-pgdump`
- using the volume created by PVC
- the init container is used to fix some owner/permissions on the directory where the volume is mounted. this is necessary since the container is not running as root but as user 1001. On KIND, this directory has 777 permissions but on other clusters, after mount, the directory is owned by root with 755 mode.
- then the main container, using environment variables to set everything and for the postgres password accessing the secret created by the helm above

After you create the PVC and the deployment, you can test things:
```
kubectl apply -f pvc.yaml 
kubectl apply -f deployment.yml
kubectl -n pg-helm get pods

# note the mypg-pgump-... name above and use it in the next command
kubectl -n pg-helm exec -ti mypg-pgdump-6cdfc4c966-kq6j2 -- bash
    # now you are 'inside' the container
    /pgdump.sh     # this will run the backup
    ls -la /data   # this will show the dumps
    exit
```

If this is working. everything is ok and you can proceed with the cronjob. Otherwise, you can use various debug commands inside the mypg-pgdump pod.

## The cronjob
Kubernetes has a dedicated object for cronjobs and this is pretty similar with a Deployment. Look at the file `cronjob.yml` where in the `spec` section you will recognize most of it. Only the `schedule` and `restartPolicy` are new. 

The schedule syntax is the same as the standard Linux cron daemon (no surprise here). You may change the `schedule:` line to see some results faster.

```
kubectl apply -f cronjob.yml
kubectl get cj 
```

## Creating the Helm chart
If you wish, uou may use the three yml files for many situations. But you will neeed to make small changes for every case: the namespace, the resources name, environment values etc. To help with this, we'll create a helm chart and use it to install with different values (other options are `kustomize` os using `sed` to do inline search-and-replaces).

Moving into `helm` directory, the file `Chart.yaml` is basically a description of the chart.

In the file `values.yaml` are the variables which can be changed at install and their default value. The namespace is not here, this and the release name will de defined in the command line.

Inside the directory `templates` you will find our three resources yml files, but slightly changed or shall I say parametrized. Everywhere you see `{{ Something }}` that is a placeholder which will be replaced during helm install. `{{ .Values.something }}` will be taken from the `values.yaml` file. Then, `{{ .Release.Name }}` and `{{ .Release.Namespace }}` are values which will be defined in the `helm install` command.

`Notes.txt` is the text displayed at the end of helm install, some sort of usage information.

## Using the Helm chart

Most probably you will want to override at least the values for `pghost` and `secret_pgpass` to match your postgresql installation. The simplest way is to copy `values.yaml` with another name, like `values_override.yaml` and edit the second file. Then use this to install the helm chart:

```
cd helm
helm upgrade --install -f values.yaml -f values_override.yaml -n <NAMESPACE> <RELEASE-NAME> . 
```

We recommend you use a release name like `<SOMETHING>-pgdump`. All the resources created by the helm chart will have this name: a PVC, a deployment and a cronjob.

Make sure you have the correct values, especially for 
- `pghost` - this should be the name of the service (svc) pointing to the postgres database and
- `secret_pgpass` - this should be the name of the secret holding the postgres password.

## Multi-Attach error for volume

While testing the helm chart I have encountered this error, in the pod spawned by the cronjob. The pod is stuck in 'Init:0/1' state and the events show:

```
kubectl -n cango-web describe pod [...]
[...]
 Warning  FailedAttachVolume  67s   attachdetach-controller  Multi-Attach error for volume "..." Volume is already used by pod(s) [...]
 Warning  FailedMount         3m44s  kubelet                  Unable to attach or mount volumes: unmounted volumes=[data], unattached volumes=[data kube-api-access-...]: timed out waiting for the condition
```

The problem is that we are mounting the same volume in the pod created by the deplyment and also in the pod created by the cronjob and the access mode is `ReadWriteOnce`. You will see this only when those pods are on different nodes since the ReadWriteOnce acces mode means the volume can be mounted only once per node.

One simple solutions will be to use `ReadWriteMany` but this is not supported by some storage classes, like DigitalOcean for example. Another way will be to give up the deployment pod which is really useful only when you want to do a database restore or for testing, debugging, verifying.

Yet another solution will be to force the cronjob pods to be spawned on the same node as the deployment pod. This is using the fact that RWO means once per node (not ince per pod!). Thus we can use inter-pod affinity, as shown in the section `affinity` from the file `helm/template/cronjob.yml`. 


## Improvments TBD 

- use volumemount when reading secret password in deployment to cope with the situation when postgres password changes (env variables are not re-read on the fly)
- storageclass in helm chart
- resource limits


