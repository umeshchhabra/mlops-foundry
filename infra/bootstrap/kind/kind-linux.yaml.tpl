kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: __MLOPS_DATA_DIR__
        containerPath: /data
    extraPortMappings:
      - { containerPort: 30080, hostPort: 8080, protocol: TCP }
      - { containerPort: 30443, hostPort: 8443, protocol: TCP }
      - { containerPort: 30500, hostPort: 5000, protocol: TCP }
      - { containerPort: 30800, hostPort: 8180, protocol: TCP }
      - { containerPort: 30900, hostPort: 9002, protocol: TCP }
      - { containerPort: 30901, hostPort: 9003, protocol: TCP }
      - { containerPort: 31080, hostPort: 8090, protocol: TCP }
      - { containerPort: 32000, hostPort: 9000, protocol: TCP }
      - { containerPort: 32001, hostPort: 9001, protocol: TCP }
  - role: worker
    extraMounts: [{ hostPath: __MLOPS_DATA_DIR__, containerPath: /data }]
  - role: worker
    extraMounts: [{ hostPath: __MLOPS_DATA_DIR__, containerPath: /data }]
  - role: worker
    extraMounts: [{ hostPath: __MLOPS_DATA_DIR__, containerPath: /data }]
