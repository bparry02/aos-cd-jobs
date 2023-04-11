The goal of this job is to create an AMI which fully encapsulates a version of OpenShift for the AWS ISO marketplace: https://issues.redhat.com/browse/OCPBU-143 .

All work done by this job is done in **us-east-2**. All AMIs it references and creates will be in that region. When AMIs are shared with target accounts, they will also only be available in us-east-2.

The scripts use packer to build a hardened base AMI (no OCP content) and an AMI with OCP content on top of the hardened base. The purpose of creating the base is that it takes a long time and we can save that time by reusing it once it is built.

It is recommended that you review how hashicorp packer works before trying to dig deeply into the implementation of this job.

The job runs tools from https://github.com/openshift/quay-image-builder to construct the AMIs. The oddest part about running these scripts is the manner in which buildvm must ssh to the hosts. A normal run of hashicorp packer:
1. Creates an AWS instance running a specific AMI  (it receives a random public IP from the AWS pool).
2. ssh's to that instance's IP.
3. Runs some commands or copies files to that instance.
4. Creates a new AMI based on the modified filesystem.

This doesn't work from buildvm because it runs a firewall blocking arbitrary outgoing connections. This means that packer cannot reach out to the dynamic public IP address when the instance comes up. To workaround this trouble, an AWS Elastic IP (EIP) has been established. When packer brings up the system, it configures the instance with a cloud-init script that assigns the EIP to the running instance. Once this occurs, packer can ssh to the system using the known EIP. If the EIP fails to be applied to the instance successfully, the packer ssh attempt will timeout.

To debug this situation, run the job with PACKER_DEBUG enabled. This will run packer with the `-debug` argument. This will cause packer to write the random ssh key it established for the new system into the job workspace on buildvm (e.g. /mnt/workspace/jenkins/working/o-marketplace-quay-image-builder/quay-image-builder/ec2_amazon-ebs.pem ). Setting the PACKER_DEBUG flag to true will also extend the packer ssh timeout from 6 minutes to 30 minutes. This should provide ample time for you to ssh to buildvm, copy the key to your local system (where you won't be constrained by the firewall), and ssh to the public IP address of the AWS EC2 instance packer instantiated.

Once successfully authenticated with the EC2 instance, you can look at the cloud-init logs to figure out why the EIP address was not successfully applied.
Key logs:
- /var/log/cloud-init-output.log (AWS mechanics write this log)
- [/var/log/packer_init.log](https://github.com/openshift/quay-image-builder/blob/d6c81f9e1db62dff1ecf7c4a2dfc190b1cb46cfd/cloud-config.sh.template#L3)

After diagnosing the issue, you can cancel the Jenkins job instead of waiting for the full 30m SSH timeout. **IMPORANT** if you do this, you must manually terminate the ec2 instance packer created in **us-east-2** .

## Testing the runner-image

1. Launch a Cloud Access 8.7 instance and install dependencies

    ```
    # ssh
    sudo -i
    yum update -y
    reboot

    # ssh
    sudo -i
    yum module install -y container-tools
    yum install -y git podman-docker
    ```

2. Register with subscription manager to get access to entitled content for the container build

    ```
    sudo subscription-manager register
    # set manage_repos = 1
    sudo vi /etc/rhsm/rhsm.conf
    ```

2. SCP the Dockerfile and other required files to the instance

    ```
    scp runner-image* ec2-user@[ip]:~/

    scp rh-registry-pull-secret.json ec2-user@[ip]:~/

    # make pull secret available for the image build
    mkdir -p ~/.docker
    cp ~/rh-registry-pull-secret.json ~/.docker/config.json
    ```

3. Build the image

    ```
    # ssh
    podman build . -f runner-image.Dockerfile -t runner-image
    ```

4. Copy quay-image-builder files

    ```
    git clone https://github.com/openshift/quay-image-builder.git

    vi quay-image-builder/build.sh
    # removed all lines after Get EIP Address. Removed AWS parameter checks
    ```

5. Optionally, run interactively,

    ```
    docker run --rm -v ~/quay-image-builder:/quay-image-builder:z -e IMAGESET_CONFIG_TEMPLATE=/quay-image-builder/imageset-config.yaml -e OCP_VER=4.12.5 -v $HOME/.docker/:/pullsecret:z -e PULL_SECRET=/pullsecret/config.json -it  runner-image /bin/bash

    oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.12
    ```

5. Test

    ```
    docker run --rm -v ~/quay-image-builder:/quay-image-builder:z -e IMAGESET_CONFIG_TEMPLATE=/quay-image-builder/imageset-config.yaml -e OCP_VER=4.12.5 -v $HOME/.docker/:/pullsecret:z -e PULL_SECRET=/pullsecret/config.json --entrypoint /quay-image-builder/build.sh runner-image
    ```
