
# Postgres backups with pg_dump - from shell scripting to Kubernetes

You may find all the files here: https://github.com/viorel-anghel/pgdump-kubernetes.git 

## Why
We are using Velero ( https://velero.io ) to do Kubernetes backups. But I feel a bit uneasy about the database backups and I have decided to also have some good old sql dumps for our Postgres databases. In VMs we have this for quite some time but for those running in Kubernetes we don't.

If you want to understand how this has been created and and learn some Kubernetes along me, read on.

If you just want to use this, skip to the section "Using the Helm chart". 

## The pgdump.sh script

This is a simple shell script based on `pg_dump` which is creating a sql dump for a database. Even if in Kubernetes is not so important, to be consistent with the style we are using in our VMs, we will dump each database in its own file. This means we are not using `pg_dumpall` but we loop over the list of dbs and dump each one with `pg_dump`.

A few notes on  how this may be different from other scripts found on the net:
- carefully checking for errors
- using environment variables `PGHOST PGPORT PGUSER PGPASSWORD` to simplify psql/pg_dump commands (see https://www.postgresql.org/docs/current/libpq-envars.html) and to be Docker/Kubernetes ready.

## The Docker image

The `Dockerfile` for building the docker image is very simple, basically we start from `bitnami/postgres` image which already has all the postgresql tools and adding the `pgdump.sh` script. 

Setting a 'do nothing' `ENTRYPOINT` is usefull in this case because you can start a container or pod from it, exec 'inside' it and test things.

Building, testing and pushing (to docker hub vvang repository) the image steps:
```
docker build -t pgdump:0.5 .        # build
docker run -d -n pgdump pgdump:0.5  # run
docker exec -ti pgdump bash         # enter in container
    ls -la /                        # run stuff inside
    exit
docker tag pgdump:0.5 vvang/pgdump:0.5  # tag
docker push vvang/pgdump:0.5            # push to docker hub
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

If you uninstall the helm chart, the PVC won't be deleted, as a safety measure for you. If you re-install it, the old PVC and postgres data will be used. 

## Kubernetes pod

I created a simple pod plus a volume to test the script functionality. 

Those are the files for this step: `pvc.yml`, `pod.yml`. Some notes on the pod:
- is using the volume created by PVC
- the init container is used to fix some owner/permissions on the directory where the volume is mounted. this is necessary since the container is not running as root but as user 1001 (due to the inherited Docker image). On KIND, this directory has 777 permissions but on other clusters, after mount, the directory is owned by root with 755 mode.
- the main container is using environment variables to set everything and for the postgres password is referencing the secret created by the helm above

I have repetead the container build and the pod creation and test many times until I was happy with the result:

```
kubectl apply -f pvc.yaml 
kubectl apply -f pod.yml
kubectl -n pg-helm get pods
kubectl -n pg-helm exec -ti mypg-pgdump -- bash
    # now you are 'inside' the container
    /pgdump.sh     # this will run the backup
    ls -la /data   # this will show the dumps
    exit
```
## Deployment and cronjob

The skeleton of the pod can now be used to create a deployment and a cronjob. Both are pretty simple once you have the pod tested and working. All the objects (pod, pvc, deployment, cronjob) will have the same name, in this case `mypg-pgdump`.

For deployment, see the file `deployment.yml`. Starting from the second `spec:` is exactly the yaml from the pod.

Apparently we would not need a deployment as long as we use `replicas: 1` but the advantage of the deployment over pod is Kubernetes will 'keep the pod alive', even if nodes in cluster are restarted or deleted. Also is easier to do version upgrades.

Kubernetes has a dedicated object for cronjobs and this is pretty similar with a Deployment. Look at the file `cronjob.yml` where in the `spec` section you will recognize most of it. Only the `schedule` and `restartPolicy` are new. 

The schedule syntax is the same as the standard Unix cron daemon (no surprise here). You may change the `schedule:` line to see some results faster.

```
kubectl apply -f cronjob.yml
kubectl get cj 
```

## Creating the Helm chart

If you wish, you may use those yml files for many situations. But you will neeed to make small changes for every case: the namespace, the resources name, the environment values etc. One of the popular solutions for this problem, in Kubernetes world, is Helm - the 'Kubernetes package manager'. Other options are `kustomize` or using `sed` to do inline search-and-replaces.

So we'll create a helm chart and use it to install with different values. Moving into `helm` directory, the file `Chart.yaml` is basically a description of the chart.

In the file `values.yaml` are the variables which can be changed at install and their default value. The namespace is not here, this and the release name will de defined at install time in the command line.

Inside the directory `templates` you will find our three resources yml files, but slightly changed or shall I say parametrized. Everywhere you see `{{ Something }}` that is a placeholder which will be replaced during helm install. `{{ .Values.something }}` will be taken from the `values.yaml` file. Then, `{{ .Release.Name }}` and `{{ .Release.Namespace }}` are values which will be defined in the `helm install` command.

`Notes.txt` is the text displayed at the end of helm install, some sort of usage information.

## Using the Helm chart

Most probably you will want to override at least the values for `pghost` and `secret_pgpass` to match your postgresql installation. The simplest way is to copy `values.yaml` with another name, like `values_override.yaml` and edit the second file. Then use this to install the helm chart:

```
cd helm
helm upgrade --install -f values_override.yaml -n <NAMESPACE> <RELEASE-NAME> . :
```

We recommend you use a release name like `<SOMETHING>-pgdump`. All the resources created by the helm chart will have this name: a PVC, a deployment and a cronjob.

Make sure you have the correct values, especially for 
- `pghost` - this should be the name of the service (svc) pointing to the postgres database and
- `secret_pgpass` - this should be the name of the secret holding the postgres password.

## Multi-Attach error for volume

While testing the helm chart I have encountered this error, in the pod created by the cronjob. The pod is stuck in 'Init:0/1' state and the events show:

```
kubectl -n cango-web describe pod [...]
[...]
 Warning  FailedAttachVolume  67s   attachdetach-controller  Multi-Attach error for volume "..." Volume is already used by pod(s) [...]
 Warning  FailedMount         3m44s  kubelet                  Unable to attach or mount volumes: unmounted volumes=[data], unattached volumes=[data kube-api-access-...]: timed out waiting for the condition
```

The problem is that we are mounting the same volume in the pod created by the deployment and also in the pod created by the cronjob and the access mode is `ReadWriteOnce`. You will see this only when those pods are on different nodes since the ReadWriteOnce acces mode means the volume can be mounted only once per node.

One simple solutions will be to use `ReadWriteMany` but this is not supported by some storage classes, like DigitalOcean for example. Another way will be to give up the deployment pod which is really useful only when you want to do a database restore or for testing, debugging, verifying.

Yet another solution will be to force the cronjob pods to be created on the same node as the deployment pod. This is using the fact that RWO means once per node, not once per pod!. Thus we can use inter-pod affinity, as shown in the section `affinity` from the file `helm/template/cronjob.yml`. 


## Improvments TBD 

- use volumemount when reading secret password in deployment to cope with the situation when postgres password changes (env variables are not re-read on the fly)
- storageclass in helm chart
- resource limits


