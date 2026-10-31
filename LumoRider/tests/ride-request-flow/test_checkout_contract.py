"""Compile the actual Foundation-only checkout contract from the app source."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / 'AddPaymentView.swift').read_text()
contract = source.split('// BEGIN RideCreationContract', 1)[1].split('\n', 1)[1].split('// END RideCreationContract', 1)[0]
tests = r'''
let id = UUID().uuidString
var passed = 0
func check(_ condition: Bool, _ name: String) {
    precondition(condition, name)
    passed += 1
    print("PASS: \(name)")
}
try RideCreationContract.validate(["id": id, "status": "requested"], scheduled: false)
check(true, "requested ride accepted")
try RideCreationContract.validate(["id": id, "status": "scheduled"], scheduled: true)
check(true, "scheduled ride accepted")
for status in ["accepted", "cancelled", "payment_pending", "completed", "", "scheduled"] {
    do {
        try RideCreationContract.validate(["id": id, "status": status], scheduled: false)
        fatalError("Unexpected status accepted: \(status)")
    } catch { check(true, "reject misleading confirmation for \(status)") }
}
for response: [String: Any] in [["status": "requested"], ["id": "bad", "status": "requested"], ["id": id]] {
    do { try RideCreationContract.validate(response, scheduled: false); fatalError("Malformed response accepted") }
    catch { check(true, "malformed response rejected") }
}
let missing = RideCreationContract.rpcError(status: 404, payload: ["code":"PGRST202"], operation: "create_passenger_fare_quote_v1")
check(missing.localizedDescription.contains("missing a required booking service"), "missing backend contract explained")
check(missing.userInfo["operation"] as? String == "create_passenger_fare_quote_v1", "failing operation retained")
let denied = RideCreationContract.rpcError(status: 401, payload: ["message":"Invalid API key"], operation: "quote")
check(denied.localizedDescription.contains("configuration was rejected"), "gateway rejection explained")
let business = RideCreationContract.rpcError(status: 422, payload: ["message":"Fare quote expired."], operation: "quote")
check(business.localizedDescription == "Fare quote expired.", "server business error preserved")
print("\(passed) checkout contract tests passed")
'''
with tempfile.TemporaryDirectory(prefix='jiylo-checkout-') as tmp:
    path = Path(tmp)
    (path/'main.swift').write_text('import Foundation\n'+contract+tests)
    subprocess.run(['swiftc', '-module-cache-path', str(path/'cache'), str(path/'main.swift'), '-o', str(path/'test')], check=True)
    subprocess.run([str(path/'test')], check=True)
