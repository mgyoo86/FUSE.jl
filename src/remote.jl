import Broker
import ZMQ

const url_balive = "tcp://127.0.0.1:6666"
const url_walive = "tcp://127.0.0.1:7777"
const url_worker = "tcp://127.0.0.1:8888"
const url_client = "tcp://127.0.0.1:9999"

function client_test(url::String=get(ENV, "FUSE_BROKER", "127.0.0.1"); url_client::String=url_client, url_balive::String=url_balive)
    ini, act = case_parameters(:FPP; version=:v1_demount, init_from=:scalars)
    return remote_run(ini, act, url; url_client, url_balive)
end

function client_tests(n_clients, url::String=get(ENV, "FUSE_BROKER", "127.0.0.1"); url_client::String=url_client, url_balive::String=url_balive)
    ini, act = case_parameters(:FPP; version=:v1_demount, init_from=:scalars)
    @sync for k in 1:n_clients
        @async remote_run(ini, act, url; url_client, url_balive)
    end
end

function remote_run(ini::ParametersAllInits, act::ParametersAllActors, url::String=get(ENV, "FUSE_BROKER", "127.0.0.1"); url_client::String=url_client, url_balive::String=url_balive)
    url_client = replace(url_client, "127.0.0.1" => url)
    url_balive = replace(url_balive, "127.0.0.1" => url)
    payload = Dict("ini" => par2dict(ini), "act" => par2dict(act))
    json_payload = JSON.sprint(payload)
    tmp = String(Broker.client(json_payload, url_client, url_balive))
    dct = JSON.parse(tmp)
    return IMAS.dict2imas(dct, IMAS.dd())
end

function worker_function(message_payload::ZMQ.Message)
    try
        json_payload = String(message_payload)
        logging(actors=Logging.Info)

        # read json input
        data = JSON.parse(json_payload, dicttype=DataStructures.OrderedDict)
        ini = dict2par!(data["ini"], ParametersAllInits())
        act = dict2par!(data["act"], ParametersAllActors())

        # init
        dd = init(ini, act)

        # run workflow
        act.ActorPFcoilsOpt.optimization_scheme = :none
        ActorWholeFacility(dd, act)

        # create json response
        json_payload = JSON.sprint(IMAS.imas2dict(dd; freeze=false))

        # return dd data
        return json_payload
    catch e
        display(e)
        return string(e)
    end
end

function worker_start(url::String=get(ENV, "FUSE_BROKER", "127.0.0.1"); url_worker::String=url_worker, url_walive::String=url_walive, url_balive::String=url_balive)
    url_worker = replace(url_worker, "127.0.0.1" => url)
    url_walive = replace(url_walive, "127.0.0.1" => url)
    url_balive = replace(url_balive, "127.0.0.1" => url)
    return Broker.worker(worker_function, url_worker, url_walive, url_balive)
end

function worker_start(n_workers::Integer, url::String=get(ENV, "FUSE_BROKER", "127.0.0.1"); url_worker::String=url_worker, url_walive::String=url_walive, url_balive::String=url_balive)
    for k in 1:n_workers
        Threads.@spawn start_worker(url; url_worker, url_walive, url_balive)
    end
end
