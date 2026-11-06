#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <sandbox.h>

static NSString *const Prelude = @"(() => {\n"
    "const show = (value) => { if (typeof value === 'string') return value; try { return JSON.stringify(value); } catch (e) { return String(value); } };\n"
    "globalThis.console = { log: (...items) => __log(items.map(show).join(' ')) };\n"
    "console.info = console.warn = console.error = console.debug = console.log;\n"
    "const withQuery = (url, query) => {\n"
    "  const pairs = Object.entries(query || {}).filter(([, v]) => v !== undefined && v !== null && v !== '');\n"
    "  if (!pairs.length) return String(url);\n"
    "  const encoded = pairs.map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v)).join('&');\n"
    "  return String(url) + (String(url).includes('?') ? '&' : '?') + encoded;\n"
    "};\n"
    "const request = (method, url, options = {}) => {\n"
    "  const body = options.json !== undefined ? JSON.stringify(options.json) : options.body;\n"
    "  const answer = __request({ method, url: withQuery(url, options.query), headers: options.headers || {}, body: body === undefined || body === null ? null : String(body) });\n"
    "  if (answer.error) throw new Error(answer.error);\n"
    "  let parsed;\n"
    "  return { status: answer.status, ok: true, text: answer.body, get json() { if (parsed === undefined) parsed = JSON.parse(answer.body); return parsed; } };\n"
    "};\n"
    "globalThis.http = { request, get: (u, o) => request('GET', u, o), post: (u, o) => request('POST', u, o), put: (u, o) => request('PUT', u, o),\n"
    "  patch: (u, o) => request('PATCH', u, o), delete: (u, o) => request('DELETE', u, o) };\n"
    "const AsyncFunction = (async () => {}).constructor;\n"
    "const describe = (e) => e && e.message ? e.message + (e.line ? ' (Zeile ' + Math.max(1, e.line - 2) + ')' : '') : String(e);\n"
    "globalThis.__start = (source, vars) => {\n"
    "  let run;\n"
    "  try { run = new AsyncFunction('vars', source); } catch (e) { __fail('Syntax: ' + describe(e)); return; }\n"
    "  run(vars).then((result) => {\n"
    "    let json;\n"
    "    try { json = JSON.stringify(result === undefined ? null : result); } catch (e) { __fail('Ergebnis ist kein JSON: ' + describe(e)); return; }\n"
    "    __done(json === undefined ? 'null' : json);\n"
    "  }, (e) => __fail(describe(e)));\n"
    "};\n"
    "})();";

static void emit(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingFragmentsAllowed error:nil];
    if (!data) data = [@"{\"error\":\"Ausgabe nicht darstellbar\"}" dataUsingEncoding:NSUTF8StringEncoding];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSDictionary *readMessage(void) {
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length = getline(&line, &capacity, stdin);
    if (length <= 0) {
        free(line);
        return nil;
    }
    NSData *data = [NSData dataWithBytesNoCopy:line length:(NSUInteger)length freeWhenDone:YES];
    id message = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [message isKindOfClass:NSDictionary.class] ? message : nil;
}

static BOOL enterSandbox(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    char *error = NULL;
    int status = sandbox_init("(version 1)(deny default)", 0, &error);
    if (error) sandbox_free_error(error);
#pragma clang diagnostic pop
    return status == 0;
}

static void warmUp(JSContext *context) {
    [context evaluateScript:@"new Date().toString(); (1234.5).toLocaleString('de-AT'); 'a'.localeCompare('b'); new Intl.DateTimeFormat('de-AT').format(new Date()); JSON.parse('{}')"];
}

int main(void) {
    @autoreleasepool {
        JSContext *context = [JSContext new];
        warmUp(context);
        if (!enterSandbox()) {
            emit(@{@"error": @"Sandbox nicht verfügbar"});
            return 1;
        }
        NSDictionary *job = readMessage();
        NSString *script = job[@"script"];
        if (![script isKindOfClass:NSString.class]) {
            emit(@{@"error": @"Kein Skript erhalten"});
            return 1;
        }

        __block BOOL finished = NO;
        void (^finish)(NSDictionary *) = ^(NSDictionary *message) {
            if (finished) return;
            finished = YES;
            emit(message);
        };
        context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
            finish(@{@"error": exception.toString ?: @"Ausnahme"});
        };
        context[@"__log"] = ^(NSString *text) {
            if (!finished) emit(@{@"log": text ?: @""});
        };
        context[@"__request"] = ^id(NSDictionary *call) {
            if (finished) return @{@"error": @"Skript ist schon beendet"};
            emit(@{@"http": call ?: @{}});
            return readMessage() ?: @{@"error": @"Keine Antwort von der Bridge"};
        };
        context[@"__done"] = ^(NSString *json) {
            id result = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]
                                                        options:NSJSONReadingFragmentsAllowed error:nil];
            finish(result ? @{@"result": result} : @{@"error": @"Ergebnis ist kein JSON"});
        };
        context[@"__fail"] = ^(NSString *message) {
            finish(@{@"error": message ?: @"Fehler"});
        };

        [context evaluateScript:Prelude];
        [context[@"__start"] callWithArguments:@[script, job[@"vars"] ?: @{}]];
        finish(@{@"error": @"Skript wartet auf etwas, das nie eintritt"});
        return 0;
    }
}
