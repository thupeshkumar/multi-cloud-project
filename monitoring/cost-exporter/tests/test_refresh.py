import sys, unittest, tempfile, json
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import refresh
class AdapterTests(unittest.TestCase):
 def test_top_summary(self): self.assertEqual(refresh.summary_cost({'monthly_cost':'1.5'}),refresh.Decimal('1.5'))
 def test_nested_summary(self): self.assertEqual(refresh.summary_cost({'summary':{'monthly_cost':2}}),2)
 def test_unknown_shape(self):
  with self.assertRaises(RuntimeError): refresh.summary_cost({'totalMonthlyCost':3})
 def invoke(self,reports,out):
  with patch.object(refresh,'run',side_effect=reports),patch.object(sys,'argv',['refresh','--out',str(out)]): refresh.main()
 def test_publish_reconciled(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'costs.json'
   self.invoke([{'currency':'USD','monthly_cost':6},{'monthly_cost':1},{'monthly_cost':2},{'monthly_cost':3}],p)
   self.assertEqual(json.loads(p.read_text())['providers'],{'aws':'1','azure':'2','gcp':'3'})
 def test_mismatch_preserves_report(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'costs.json';p.write_text('previous')
   with self.assertRaises(RuntimeError): self.invoke([{'currency':'USD','monthly_cost':99},{'monthly_cost':1},{'monthly_cost':2},{'monthly_cost':3}],p)
   self.assertEqual(p.read_text(),'previous')
 def test_missing_value_preserves_report(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'costs.json';p.write_text('previous')
   with self.assertRaises(RuntimeError): self.invoke([{'currency':'USD','monthly_cost':6},{'monthly_cost':None},{'monthly_cost':2},{'monthly_cost':3}],p)
   self.assertEqual(p.read_text(),'previous')
if __name__=='__main__': unittest.main()
