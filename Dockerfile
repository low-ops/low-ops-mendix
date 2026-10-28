# Dockerfile to create a Mendix Docker image based on either the source code or
# Mendix Deployment Archive (aka mda file)
#
# Author: Mendix Digital Ecosystems, digitalecosystems@mendix.com
# Version: 5.1.0
ARG ROOTFS_IMAGE=mendix-rootfs:app
ARG BUILDER_ROOTFS_IMAGE=mendix-rootfs:builder

# Build stage
FROM ${BUILDER_ROOTFS_IMAGE} AS builder

# Build-time variables
ARG BUILD_PATH=project
ARG DD_API_KEY=lowops
ENV APPMETRICS_TARGET='{"url": "http://localhost/write"}'
ENV DD_API_KEY=${DD_API_KEY}

# Exclude the logfilter binary by default
ARG EXCLUDE_LOGFILTER=true

# Allow specification of alternative BLOBSTORE location and debugging
ARG BLOBSTORE
ARG BUILDPACK_XTRACE

# Copy project model/sources
COPY $BUILD_PATH /opt/mendix/build

# Use nginx supplied by the base OS
ENV NGINX_CUSTOM_BIN_PATH=/usr/sbin/nginx

# needed for telegraf
RUN cp /opt/mendix/buildpack/dependencies.yml /tmp/dependencies.yml

# Copy start scripts
COPY scripts/startup.py scripts/vcap_application.json /opt/mendix/build/

# Each comment corresponds to the script line:
# 1. Create cache directory and directory for dependencies which can be shared
# 2. Set permissions for compilation scripts
# 3. Navigate to buildpack directory
# 4. Call compilation script
# 5. Remove temporary files
# 6. Create symlink for java prefs used by CF buildpack
# 7. Update ownership of /opt/mendix so that the app can run as a non-root user
# 8. Update permissions of /opt/mendix so that the app can run as a non-root user
RUN mkdir -p /tmp/buildcache/bust /tmp/cf-deps /var/mendix/build /var/mendix/build/.local &&\
    chmod +rx /opt/mendix/buildpack/compilation.py /opt/mendix/buildpack/buildpack/stage.py /opt/mendix/build/startup.py &&\
    cd /opt/mendix/buildpack &&\
    ./compilation.py /opt/mendix/build /tmp/buildcache /tmp/cf-deps 0 &&\
    rm -fr /tmp/buildcache /tmp/javasdk /tmp/opt /tmp/downloads /opt/mendix/buildpack/compilation.py /var/mendix &&\
    ln -s /opt/mendix/.java /opt/mendix/build &&\
    chown -R ${USER_UID}:0 /opt/mendix &&\
    chmod -R g=u /opt/mendix

RUN cp /tmp/dependencies.yml /opt/mendix/build/dependencies.yml

FROM ${ROOTFS_IMAGE}
LABEL Author="Mendix Digital Ecosystems"
LABEL maintainer="digitalecosystems@mendix.com"

# Install Ruby if Datadog is detected
ARG DD_API_KEY

# Set the user ID
ARG USER_UID=1001
# Set the home path
ENV HOME=/opt/mendix/build
ENV APPMETRICS_TARGET='{"url": "http://localhost/write"}'

# Allow the user group to modify /etc/passwd so that OpenShift 3 randomized UIDs are supported by CF Buildpack 
RUN chmod g=u /etc/passwd &&\
    chown ${USER_UID}:0 /etc/passwd

# Add the buildpack modules
ENV PYTHONPATH "/opt/mendix/buildpack/lib/:/opt/mendix/buildpack/:/opt/mendix/buildpack/lib/python3.11/site-packages/"

# Create vcap home directory for Datadog configuration
RUN mkdir -p /home/vcap /opt/datadog-agent/run &&\
    chown -R ${USER_UID}:0 /home/vcap /opt/datadog-agent/run &&\
    chmod -R g=u /home/vcap /opt/datadog-agent/run

USER ${USER_UID}

# Copy build artifacts from build container
COPY --from=builder /opt/mendix /opt/mendix

# Use nginx supplied by the base OS
ENV NGINX_CUSTOM_BIN_PATH=/usr/sbin/nginx

WORKDIR /opt/mendix/build

# Expose nginx port
ENV PORT 8080
EXPOSE $PORT

# needed for metrics to work
RUN sed -i '/^  admin_port:.*/a \ \ admin_listen_addresses: "*"' ./.local/m2ee.yaml
# needed for telegraf
RUN echo -e "\n[[outputs.prometheus_client]] \nlisten = \":9273\"\nexpiration_interval = \"300s\"\nmetric_version = 2\ncollectors_exclude = [\"gocollector\", \"process\"]\n" >> ./.local/telegraf/telegraf-1.24.4/etc/telegraf/telegraf.toml.j2
RUN sed -i 's/e\["DD_HOSTNAME"\] = util.get_hostname()/e\["DD_HOSTNAME"\] = os.environ.get("DD_HOSTNAME", util.get_hostname())/g' buildpack/telemetry/datadog.py

ENTRYPOINT ["/opt/mendix/build/startup.py"]
