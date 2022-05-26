
# Postgres backups with pg_dump - from shell scripting to Kubernetes

You may find all the files here: https://github.com/viorel-anghel/pgdump-kubernetes.git 

## Why
We are using Velero ( https://velero.io ) to do Kubernetes backups. But I feel a bit uneasy about the database backups and I have decided to also have some good old sql dumps for our Postgres databases. In VMs we have this for quite some time but for those running in Kubernetes we don't.

If you want to understand how this has been created and and learn some Kubernetes along me, read on.

If you just want to use this, see the `helm` directory, the section "Using the Helm chart". 

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

We would not really need the deployment but it makes me confortable to know that I can inspect the backups at any time by exec-ing into that pod. Also it is very easy to do a restore from it. For deployment declaration, see the file `deployment.yml`. Starting from the second `spec:` is exactly the yaml from the pod.

Apparently we would not need a deployment as long as we use `replicas: 1` but a pod. The advantage of the deployment over pod is Kubernetes will 'keep the pod alive', even if some nodes in the cluster are restarted or deleted. Also it's easier to do version upgrades.

Kubernetes has a dedicated object for cronjobs and this is pretty similar with a Deployment. Look at the file `cronjob.yml` where in the `spec` section you will recognize most of it. Only the `schedule` and `restartPolicy` are new. 

The schedule syntax is the same as the standard Unix cron daemon (no surprise here). You may change the `schedule:` line to see some results faster (use '* * * * *' for every minute).

```
kubectl apply -f cronjob.yml
kubectl get cj 
```

## Part 2 - working with Helm
Continue with the `helm` directory.

