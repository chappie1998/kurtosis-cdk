ports_package = import_module("../src/package_io/ports.star")

CDK_ERIGON_TYPE = struct(
    sequencer="sequencer",
    rpc="rpc",
)


def start_cdk_erigon_sequencer(plan, args, config_artifact, start_port_name):
    ports = {
        "data-streamer": PortSpec(
            args["zkevm_data_streamer_port"], application_protocol="datastream"
        )
    }
    env_vars = {"CDK_ERIGON_SEQUENCER": "1"}
    _start_service(
        plan,
        CDK_ERIGON_TYPE.sequencer,
        args,
        config_artifact,
        start_port_name,
        ports,
        env_vars,
    )


def start_cdk_erigon_rpc(plan, args, config_artifact, start_port_name):
    _start_service(plan, CDK_ERIGON_TYPE.rpc, args, config_artifact, start_port_name)


def _start_service(
    plan, type, args, config_artifact, start_port_name, additional_ports={}, env_vars={}
):
    cdk_erigon_chain_artifact_names = [
        config_artifact.chain_spec,
        config_artifact.chain_config,
        config_artifact.chain_allocs,
        config_artifact.chain_first_batch,
    ]
    plan_files = {
        "/etc/cdk-erigon": Directory(
            artifact_names=[config_artifact.config] + cdk_erigon_chain_artifact_names,
        ),
        "/home/erigon/dynamic-configs/": Directory(
            artifact_names=cdk_erigon_chain_artifact_names,
        ),
    }

    proc_runner_file_artifact = plan.upload_files(
        name="cdk-erigon-" + type + "-proc-runner",
        src="../templates/proc-runner.sh",
    )
    plan_files["/usr/local/share/proc-runner"] = proc_runner_file_artifact

    if args["erigon_datadir_archive"] != None:
        existing_datadir_artifact = plan.upload_files(
            src=args["erigon_datadir_archive"],
        )
        plan_files[
            "/home/erigon/data/dynamic-" + args["chain_name"] + "-sequencer"
        ] = existing_datadir_artifact

    (ports, public_ports) = get_cdk_erigon_ports(
        args, additional_ports, start_port_name
    )

    service_name = "cdk-erigon-" + type + args["deployment_suffix"]
    image = args["cdk_erigon_node_image"]
    entrypoint = ["/usr/local/share/proc-runner/proc-runner.sh"]
    cmd = ["cdk-erigon", "--config", "/etc/cdk-erigon/config.yaml"]

    # Construct the equivalent Docker command
    docker_command = f"docker run -d \\\n"
    docker_command += f"    --name {service_name} \\\n"
    docker_command += f"    --user 0:0 \\\n"

    # Add port mappings
    for port_id, port_spec in public_ports.items():
        docker_command += f"    -p {port_spec.number}:{ports[port_id].number} \\\n"

    # Add environment variables
    for key, value in env_vars.items():
        docker_command += f"    -e {key}={value} \\\n"

    # Add volume mounts
    for container_path, artifact in plan_files.items():
        docker_command += f"    -v {artifact}:{container_path} \\\n"

    # Add entrypoint
    docker_command += f"    --entrypoint {' '.join(entrypoint)} \\\n"

    # Add image
    docker_command += f"    {image} \\\n"

    # Add command
    docker_command += f"    {' '.join(cmd)}"

    # Print the Docker command
    plan.print("Equivalent Docker command to start the service:")
    plan.print(docker_command)

    # Add the service
    plan.add_service(
        name=service_name,
        config=ServiceConfig(
            image=image,
            ports=ports,
            user=User(uid=0, gid=0),
            public_ports=public_ports,
            files=plan_files,
            entrypoint=entrypoint,
            cmd=cmd,
            env_vars=env_vars,
        ),
    )


def get_cdk_erigon_ports(args, additional_ports, start_port_name):
    ports = {
        "pprof": PortSpec(
            args["zkevm_pprof_port"], application_protocol="http", wait=None
        ),
        "prometheus": PortSpec(
            args["prometheus_port"], application_protocol="http", wait=None
        ),
        "rpc": PortSpec(args["zkevm_rpc_http_port"], application_protocol="http"),
        "ws-rpc": PortSpec(args["zkevm_rpc_ws_port"], application_protocol="ws"),
    } | additional_ports
    public_ports = ports_package.get_public_ports(ports, start_port_name, args)
    return (ports, public_ports)
