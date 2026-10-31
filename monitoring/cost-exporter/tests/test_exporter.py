import importlib.util,json,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('exporter',ROOT/'exporter.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
class ReportTests(unittest.TestCase):
 def base(self):return {'schema_version':1,'currency':'USD','generated_at':'2026-10-31T00:00:00+00:00','providers':{'aws':'10.5','azure':'20','gcp':'3'}}
 def render(self,data,now=None):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'costs.json';p.write_text(json.dumps(data));return e.metrics(p,now=1793404800 if now is None else now)
 def test_missing_file_no_false_zero(self):
  s=e.metrics('/missing-costs-file');self.assertIn('cost_exporter_report_valid 0',s);self.assertNotIn('cloud_estimated_monthly_cost_usd{',s)
 def test_valid(self):
  d=self.base();epoch,_=e.parse_report(d,time.time()+999999999);s=self.render(d,epoch+60);self.assertIn('cloud_estimated_monthly_cost_usd{cloud="aws"} 10.5',s)
 def test_stale_suppresses_cost(self):
  d=self.base();epoch,_=e.parse_report(d,time.time()+999999999);s=self.render(d,epoch+90000);self.assertIn('cost_exporter_report_stale 1',s);self.assertNotIn('cloud_estimated_monthly_cost_usd{',s)
 def test_missing_cloud_is_not_zero(self):
  d=self.base();d['providers'].pop('gcp');epoch,_=e.parse_report(d,time.time()+999999999);s=self.render(d,epoch+60);self.assertIn('cost_exporter_estimate_available{cloud="gcp"} 0',s);self.assertNotIn('cloud_estimated_monthly_cost_usd{cloud="gcp"}',s)
 def test_true_zero_is_kept(self):
  d=self.base();d['providers']['gcp']='0';epoch,_=e.parse_report(d,time.time()+999999999);self.assertIn('cloud_estimated_monthly_cost_usd{cloud="gcp"} 0',self.render(d,epoch+60))
 def test_non_usd_rejected(self):
  d=self.base();d['currency']='INR';self.assertIn('cost_exporter_report_valid 0',self.render(d))
 def test_future_rejected(self):
  d=self.base();d['generated_at']='2099-01-01T00:00:00Z';self.assertIn('cost_exporter_report_valid 0',self.render(d))
 def test_nan_rejected(self):
  d=self.base();d['providers']['aws']='NaN';self.assertIn('cost_exporter_report_valid 0',self.render(d))
 def test_negative_rejected(self):
  d=self.base();d['providers']['aws']='-3';self.assertIn('cost_exporter_report_valid 0',self.render(d))
 def test_timezone_required(self):
  d=self.base();d['generated_at']='2026-10-31T00:00:00';self.assertIn('cost_exporter_report_valid 0',self.render(d))
 def test_unknown_schema_rejected(self):
  self.assertIn('cost_exporter_report_valid 0',self.render({'summary':{'monthly_cost':33}}))
if __name__=='__main__':unittest.main()
