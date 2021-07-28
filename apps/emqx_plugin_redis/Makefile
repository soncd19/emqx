## shallow clone for speed

PROJECT = emqx_plugin_redis
PROJECT_DESCRIPTION = EMQ X Redis Plugin
PROJECT_VERSION = 3.2.2

REBAR_GIT_CLONE_OPTIONS += --depth 1
export REBAR_GIT_CLONE_OPTIONS

REBAR = rebar3
all: compile

compile:
	$(REBAR) compile

ct: compile
	$(REBAR) as test ct -v

eunit: compile
	$(REBAR) as test eunit

xref:
	$(REBAR) xref

cover:
	$(REBAR) cover

clean: distclean

distclean:
	@rm -rf _build
	@rm -f data/app.*.config data/vm.*.args rebar.lock

$(CUTTLEFISH_SCRIPT):
	@${REBAR} get-deps
	@if [ ! -f cuttlefish ]; then make -C _build/default/lib/cuttlefish; fi

app.config: $(CUTTLEFISH_SCRIPT) etc/emqx_plugin_redis.conf
	$(verbose) $(CUTTLEFISH_SCRIPT) -l info -e etc/ -c etc/emqx_plugin_redis.conf -i priv/emqx_plugin_redis.schema -d data
