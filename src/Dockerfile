FROM rclone/rclone:1.69.0

RUN apk add --no-cache bash git git-lfs jq

RUN git lfs install

ENV HOME /home/shared
RUN mkdir --parents --mode=777 $HOME

COPY entrypoint.sh /entrypoint.sh
COPY scripts /usr/local/bin

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--backup-immediately"]
