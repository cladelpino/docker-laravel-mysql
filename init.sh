#!/bin/bash
docker-compose down
relevantVolumeName="misma-data-local_persistent"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
echo "************"
echo "Script directory is $SCRIPT_DIR, this will be used as root for all paths"
echo "************"
existingVolumes=$(docker volume ls -q)
if [[ "$existingVolumes" == *"$relevantVolumeName"* ]]; then
    echo "************"
    echo "Volume: $relevantVolumeName detected."
    echo "************"
    volumeExists=1
else
    echo "************"
    echo "Volume: $relevantVolumeName not detected. It will be created, and a fresh start for DBs will be made."
    echo "************"
    volumeExists=0
    freshStart=1
fi
if [[ $# == 0 && $volumeExists -gt 0 ]]; then
    echo "************"
    echo "No arguments provided, and persistent mysql volume exists. Remember, you can use --fresh if you want a fresh DBs start."
    echo "************"
    freshStart=0
elif [[ $1 == "--fresh" && $volumeExists -gt 0 ]]; then
    echo "************"
    echo "Fresh DBs Start requested."
    echo "************"
    freshStart=1
    echo "************"
    echo "Removing volume:"
    echo "************"
    docker volume rm "$relevantVolumeName"
fi
if [[ $freshStart == 1 ]]; then
    sed -i -e 's/^\([[:space:]]*\)#\([[:space:]]*-[[:space:]]*\.\/dumps:\/home\/dumps:ro[[:space:]]*\)$/\1\2/g
' docker-compose.yml
    docker-compose up -d
    while ! docker-compose exec db mysql --user=root --password=test -e "SELECT 1" >/dev/null 2>&1; do
        echo "Waiting for DB server..."
        sleep 2
    done

    for d in ./dumps/*/; do
        
        p=$(sed -e 's/\.\/dumps\/\(.*\)\//\1/g' <<< "$d")

        echo $d
        echo "************"
        echo "Creating database $p"
        echo "************"
        
        docker-compose exec db mysql --user=root --password=test --show-warnings -e "CREATE DATABASE $p" &> >(tee -a >(sed "s/^/$(date) /" >> ./sqllog.log))
        
        for f in $d*; do
            echo "************"
            echo "Loading dump from $f"
            echo "************"
            t=$(sed -e "s/\.\/dumps\/"$p"\/\(.*\)/\1/g" <<< "$f")
            echo $t
            docker-compose exec db sh -c "mysql --user=root --password=test --show-warnings $p < /home/dumps/$p/$t" &> >(tee -a >(sed "s/^/$(date) /" >> ./sqllog.log))
        done
    done

    docker-compose exec db sh -c "rm var/lib/mysql/*.pem && mysql_ssl_rsa_setup -v --suffix='db'" &> >(tee -a >(sed "s/^/$(date) /" >> ./sqllog.log))
    docker-compose exec db sh -c 'cat var/lib/mysql/ca.pem' > ./data_app/ca.pem &> >(tee -a >(sed "s/^/$(date) /" >> ./sqllog.log))
    docker-compose down
fi
sed -i -e 's/^\([[:space:]]*\)\(-[[:space:]]*\.\/dumps:\/home\/dumps:ro[[:space:]]*\)$/\1#\2/g' docker-compose.yml
docker-compose up