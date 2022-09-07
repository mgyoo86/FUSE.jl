import Broker

const url_balive = "tcp://127.0.0.1:6666"
const url_walive = "tcp://127.0.0.1:7777"
const url_worker = "tcp://127.0.0.1:8888"
const url_client = "tcp://127.0.0.1:9999"

function client_test(url::String="127.0.0.1"; url_client::String=url_client)
    ini, act = FUSE.case_parameters(:FPP; version=:v1_demount, init_from=:scalars);
    return remote_run(ini, act, url; url_client)
end

function client_tests(n_clients, url::String="127.0.0.1"; url_client::String=url_client)
    @sync for k in 1:n_clients
        @async client_test(url; url_client)
    end
end

function remote_run(ini::ParametersAllInits, act::ParametersAllActors, url::String="127.0.0.1"; url_client::String=url_client)
    url_client = replace(url_client, "127.0.0.1"=>url)
    payload = Dict("ini" => FUSE.par2dict(ini), "act" => FUSE.par2dict(act))
    json_payload = FUSE.JSON.sprint(payload)
    tmp = Broker.client(json_payload, url_client)
    dct = FUSE.JSON.parse(String(tmp))
    return IMAS.dict2imas(dct, IMAS.dd())
end

function worker_function(json_payload::String)
    try
        # read json input
        tmp = JSON.parse(json_payload, dicttype=DataStructures.OrderedDict)
        ini = FUSE.dict2par!(tmp["ini"], FUSE.ParametersAllInits())
        act = FUSE.dict2par!(tmp["act"], FUSE.ParametersAllActors())

        # init
        dd = FUSE.init(ini, act)

        # run workflow
        act.ActorPFcoilsOpt.optimization_scheme = :none
        FUSE.ActorWholeFacility(dd, act)

        # return dd data
        return FUSE.JSON.sprint(IMAS.imas2dict(dd; freeze=false))
    catch e
        display(e)
        return string(e)
    end
end

function worker_start(url::String="127.0.0.1"; url_worker::String=url_worker, url_walive::String=url_walive, url_balive::String=url_balive)
    url_worker = replace(url_worker, "127.0.0.1"=>url)
    url_walive = replace(url_walive, "127.0.0.1"=>url)
    url_balive = replace(url_balive, "127.0.0.1"=>url)
    return Broker.worker(worker_function, url_worker, url_walive, url_balive)
end

function worker_start(n_workers::Integer, url::String="127.0.0.1"; url_worker::String=url_worker, url_walive::String=url_walive, url_balive::String=url_balive)
    for k in 1:n_workers
        Threads.@spawn start_worker(url; url_worker, url_walive, url_balive)
    end
end
