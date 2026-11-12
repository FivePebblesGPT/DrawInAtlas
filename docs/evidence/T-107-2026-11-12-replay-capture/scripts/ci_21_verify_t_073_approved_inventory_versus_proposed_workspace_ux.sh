set -euo pipefail
python3 -m unittest discover -s tests -p 'test_t073_feature_ux_docs.py' -v
python3 -m unittest discover -s tests -p 'test_t094_owner_matrix.py' -v
python3 -m unittest discover -s tests -p 'test_t078_t083_docking_plan.py' -v
python3 -m unittest discover -s tests -p 'test_t094_owner_evidence.py' -v
python3 -m unittest discover -s tests -p 'test_t094_ci_replay.py' -v
python3 -m unittest discover -s tests -p 'test_t094_hosted_ci_evidence.py' -v
python3 -m unittest discover -s tests -p 'test_t094_godot_model_log.py' -v
