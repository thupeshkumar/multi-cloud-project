from pathlib import Path
import importlib.util, unittest, sys, os, io, contextlib
from unittest.mock import patch
base=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('failover',base/'failover/failover.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
origins=[{'name':c,'ip':ip,'url':'http://'+ip+'/health'} for c,ip in [('aws','192.0.2.1'),('azure','192.0.2.2'),('gcp','192.0.2.3')]]
class EndLoop(Exception): pass
class Tests(unittest.TestCase):
    def scenario(self,active,bad,cycles=4,wrong=False,api_error=False):
        writes=[]; sleeps=0
        def request(url,method='GET',data=None,token=None):
            if 'cloudflare.com' in url:
                if api_error: raise RuntimeError('simulated API failure')
                if method=='PATCH': writes.append(data); return 200,b'{"success":true}'
                return 200,m.json.dumps({'success':True,'result':{'type':'A','name':'app.example.com','proxied':wrong,'content':active}}).encode()
            o=next(o for o in origins if o['url']==url)
            if o['name'] in bad: raise OSError('simulated outage')
            return 200,('healthy '+o['name']).encode()
        def sleep(_):
            nonlocal sleeps
            sleeps+=1
            if sleeps>=cycles: raise EndLoop()
        env={'CF_API_TOKEN':'dummy','CF_ZONE_ID':'dummy','CF_RECORD_ID':'dummy','CF_RECORD_NAME':'app.example.com'}
        with patch.object(m.Path,'read_text',return_value=m.json.dumps(origins)),patch.object(m,'request',side_effect=request),patch.object(m.time,'sleep',side_effect=sleep),patch.object(m.time,'monotonic',return_value=1000),patch.dict(os.environ,env),patch.object(sys,'argv',['failover','--cooldown','1']),contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(EndLoop): m.run()
        return writes
    def test_failover_to_azure(self): self.assertEqual(self.scenario('192.0.2.1',{'aws'})[0]['content'],'192.0.2.2')
    def test_failover_to_gcp(self): self.assertEqual(self.scenario('192.0.2.1',{'aws','azure'})[0]['content'],'192.0.2.3')
    def test_all_unhealthy_retains_dns(self): self.assertEqual(self.scenario('192.0.2.1',{'aws','azure','gcp'}),[])
    def test_transient_outage_no_write(self): self.assertEqual(self.scenario('192.0.2.1',{'aws'},cycles=2),[])
    def test_failback(self): self.assertEqual(self.scenario('192.0.2.2',set())[0]['content'],'192.0.2.1')
    def test_proxy_guard(self): self.assertEqual(self.scenario('192.0.2.1',{'aws'},wrong=True),[])
    def test_api_error_no_write(self): self.assertEqual(self.scenario('192.0.2.1',{'aws'},api_error=True),[])
if __name__=='__main__': unittest.main()
