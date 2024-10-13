/* [[file:../nubs.org::*Emscripten Threads][Emscripten Threads:3]] */
#include <emscripten/emscripten.h>
#include <emscripten/console.h>
#include <emscripten/wasm_worker.h> // TODO
#include <pthread.h>

int wrap_size_pthread_t () { return sizeof(pthread_t); }
int wrap_size_pthread_mutex_t () { return sizeof(pthread_mutex_t); }
int wrap_size_pthread_cond_t () { return sizeof(pthread_cond_t); }

int wrap_pthread_create (pthread_t *t, const pthread_attr_t *tattr,
                         void *(*start_routine)(void *), void *arg) {
	pthread_attr_t thread_attr;
	pthread_attr_init(&thread_attr);
	pthread_attr_setdetachstate(&thread_attr, PTHREAD_CREATE_DETACHED);
	int ret = pthread_create(t, &thread_attr/*TODO: tattr*/, start_routine, arg);
	pthread_attr_destroy(&thread_attr);
	return ret;
}

int wrap_pthread_detach (pthread_t t) {
	return pthread_detach(t);
}

int wrap_pthread_join (pthread_t t, void **status) {
	return pthread_join(t, status);
}

int wrap_pthread_mutex_init (pthread_mutex_t *m, const pthread_mutexattr_t *mattr) {
	return pthread_mutex_init(m, mattr);
}

int wrap_pthread_mutex_destroy (pthread_mutex_t *m) {
	return pthread_mutex_destroy(m);
}

int wrap_pthread_mutex_lock (pthread_mutex_t *m) {
	return pthread_mutex_lock(m);
}

int wrap_pthread_mutex_unlock (pthread_mutex_t *m) {
	return pthread_mutex_unlock(m);
}

int wrap_pthread_cond_init (pthread_cond_t *c, const pthread_condattr_t *cattr) {
	return pthread_cond_init(c, cattr);
}

int wrap_pthread_cond_destroy (pthread_cond_t *c) {
	return pthread_cond_destroy(c);
}

int wrap_pthread_cond_wait (pthread_cond_t *cond, pthread_mutex_t *m) {
	return pthread_cond_wait(cond, m);
}

int wrap_pthread_cond_signal (pthread_cond_t *cond) {
	return pthread_cond_signal(cond);
}

void wrap_emscripten_console_log (const char *str) {
	emscripten_console_log(str);
}

// ------------------------------

extern void _main();
extern void step();

int main() {
	_main();

	emscripten_set_main_loop(step, 0, 1);
	return 0;
}
/* Emscripten Threads:3 ends here */
