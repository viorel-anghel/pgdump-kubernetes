# Postgres backups with pg_dump - from shell scripting to Kubernetes
# part 2 - working with Helm

This is the second part, discussing how to convert from static yaml files to Helm. See the first part here 
https://github.com/viorel-anghel/pgdump-kubernetes.git 


## Creating the Helm chart

If you wish, you may use those yml files for many situations. But you will neeed to make small changes for every case: the namespace, the resources name, the environment values etc. One of the popular solutions for this problem, in Kubernetes world, is Helm - the 'Kubernetes package manager'. Other options are `kustomize` os using `sed` to do inline search-and-replaces.

So we'll create a helm chart and use it to install with different values. In the `helm` directory, the file `Chart.yaml` is basically a description of the chart.

The file `values.yaml` contains the variables which can be changed at install together with their default value. The namespace is not here, this and the release name will de defined at install time in the command line.

Inside the directory `templates` you will find our three resources yml files, but slightly changed or shall I say parametrized. Everywhere you see `{{ Something }}` that is a placeholder which will be replaced during helm install. `{{ .Values.something }}` will be taken from the `values.yaml` file. Then, `{{ .Release.Name }}` and `{{ .Release.Namespace }}` are values which will be defined in the `helm install` command.

`Notes.txt` is the text displayed at the end of helm install, some sort of usage information.

## Publishing the Helm chart

TBD

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


