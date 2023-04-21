# els 8.6-921. Version doesn't really matter here as long as repos runnerimage.repo
# provides repos for the same RHEL version.
FROM registry.redhat.io/ubi8/ubi:8.7-1112

USER 0

ADD runner-image.repo /etc/yum.repos.d/

RUN dnf install -y dnf-plugins-core && \
    dnf install -y packer git ansible-core python3-pip jq skopeo && \
    curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz | tar zxv --directory /usr/bin && chmod +x /usr/bin/oc-mirror && \
    curl -L https://github.com/mikefarah/yq/releases/download/v4.30.6/yq_linux_amd64.tar.gz | tar xzv --directory /usr/bin && \
    mv /usr/bin/yq_linux_amd64 /usr/bin/yq && \
    pip3 install awscli && \
    dnf clean all

WORKDIR /quay-image-builder
