#!/bin/bash

# postgres commands assume the environment variables are defined
# PGHOST PGPORT PGUSER PGPASSWORD
# as per https://www.postgresql.org/docs/current/libpq-envars.html
# this is why psql/pg_dump are working with no additional arguments

# env var WORKDIR is used as the location for dumps

echo starting $0

if touch $WORKDIR/tmpfile
then
  rm $WORKDIR/tmpfile
else
  echo "unable to write to $WORKDIR"
  exit 1
fi

cd $WORKDIR

if psql -c 'select datname from pg_database;' >dblist.raw
then
  :
else
  echo "psql failed to connect. check environment variables"
  exit 2
fi

cat dblist.raw | while read line
do
    set -- $line
    db=$1
    [ "$db" ] || continue
    [ "$db" = "datname" ] && continue
    [ "$db" = "template0" ] && continue

    echo "$db" | egrep -q '^--' && continue
    echo "$db" | egrep -q '^\(' && continue

    if pg_dump $db >${db}.sql
    then
      echo pgdump $db done. now gzipping
      mv ${db}.sql.gz ${db}-old.sql.gz 2>/dev/null
      if gzip ${db}.sql
      then
        :
      else
        echo pgdump failed on gzip $db
      fi
    else
      echo pgdump failed on db $db
    fi 
done

echo done with $0

