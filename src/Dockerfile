FROM rclone/rclone:1.68.1

RUN apk add --no-cache bash git git-lfs jq

RUN git lfs install

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
