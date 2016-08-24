TEST_SCENARIOS="[1-8]*"
TEST_URL='ws://localhost:9001/'

all:
	$(MAKE) -C SocketRocket

clean:
	$(MAKE) -C SocketRocket clean

.env:

	./TestSupport/setup_env.sh .env

test: .env

	mkdir -p pages/results
	bash ./TestSupport/run_test_server.sh $(TEST_SCENARIOS) $(TEST_URL) Debug || open pages/results/index.html && false
	open pages/results/index.html

test_all: .env

	mkdir -p pages/results
	bash ./TestSupport/run_test_server.sh '*' $(TEST_URL) Debug || open pages/results/index.html && false
	open pages/results/index.html

test_perf: .env

	mkdir -p pages/results
	bash ./TestSupport/run_test_server.sh '9.*' $(TEST_URL) Release || open pages/results/index.html && false
	open pages/results/index.html
