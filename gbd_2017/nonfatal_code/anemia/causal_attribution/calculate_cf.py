import pandas as pd
import scipy.stats as sp
import argparse

hgb_file = FILEPATH
idcols = ['location_id', 'year_id', 'age_group_id', 'sex_id']


def get_cf(year_id, sex_id, age_group_id):
    hb_est = pd.read_hdf(
                hgb_file,
                where="year_id==%s & sex_id==%s & age_group_id==%s" % (year_id, sex_id, age_group_id))

    for d in range(1000):
        hb_est['hgb_pop_normal_{}'.format(d)] = sp.scoreatpercentile(hb_est['hgb_{}'.format(d)], 95)
        hb_est['draw_{}'.format(d)] = hb_est[['hgb_{}'.format(d), 'hgb_pop_normal_{}'.format(d)]].max(axis=1)

    names = [c for c in list(hb_est) if (c[:4] == 'draw')] + idcols
    cf_hb = hb_est[names]
    cf_hb.to_csv('FILEPATH/%s_%s_%s.csv' % (year_id, sex_id, age_group_id))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("year_id", help="year to use", type=int)
    parser.add_argument("sex_id", help="sex id to use", type=int)
    parser.add_argument("age_group_id", help="age group to use", type=int)
    args = parser.parse_args()
    get_cf(args.year_id, args.sex_id, args.age_group_id)
