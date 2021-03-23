use crate::helper::{load_module_test, run_top_level_test_no_args, run_top_level_test_with_args};

// issue #857
#[test]
fn display_constraints() {
    run_top_level_test_no_args(
        "\
        X = 1.\n\
        use_module(library(dif)).\n\
        X = 1.\n\
        dif(X,1).\n",
        "   \
        X=1.\n   \
        true.\n   \
        X=1.\n   \
        dif:dif(X,1).\n\
        ",
    );
}

// issue #852
#[test]
fn do_not_duplicate_path_components() {
    run_top_level_test_no_args(
        "\
            ['tests-pl/issue852-throw_e.pl'].\n\
            ['tests-pl/issue852-throw_e.pl'].\n\
            ",
        "\
        caught: e\n\
        caught: e\n\
        ",
    );
}

// issue #844
#[test]
fn handle_residual_goal() {
    run_top_level_test_no_args(
        "\
        use_module(library(dif)).\n\
        use_module(library(atts)).\n\
        -X\\=X.\n\
        -X=X.\n\
        dif(-X,X).\n\
        dif(-X,X), -X=X.\n\
        call_residue_vars(dif(-X,X), Vars).\n\
        set_prolog_flag(occurs_check, true).\n\
        -X\\=X.\n\
        dif(-X,X).\n\
        ",
        "   \
        true.\n   \
        true.\n   \
        false.\n   \
        X= -X.\n   \
        dif:dif(-X,X).\n   \
        false.\n   \
        Vars=[X], dif:dif(-X,X).\n   \
        true.\n   \
        true.\n   \
        true.\n\
        ",
    )
}

// issue #841
#[test]
fn occurs_check_flag() {
    run_top_level_test_with_args(
        &["tests-pl/issue841-occurs-check.pl"],
        "\
            f(X, X).\n\
            ",
        "   false.\n",
    )
}

#[test]
fn occurs_check_flag2() {
    run_top_level_test_no_args(
        "\
            set_prolog_flag(occurs_check, true).\n\
            X = -X.\n\
            asserta(f(X,g(X))).\n\
            f(X,X).\n\
            X-X = X-g(X).
            ",
        "   \
            true.\n   \
            false.\n   \
            true.\n   \
            false.\n   \
            false.\n\
            ",
    )
}

// issue #839
#[test]
fn op3() {
    run_top_level_test_with_args(&["tests-pl/issue839-op3.pl"], "", "")
}

// issue #820
#[test]
fn multiple_goals() {
    run_top_level_test_with_args(
        &["-g", "test", "-g", "halt", "tests-pl/issue820-goals.pl"],
        "",
        "helloworld\n",
    );
}

// issue #820
#[test]
fn compound_goal() {
    run_top_level_test_with_args(
        &["-g", "test,halt", "tests-pl/issue820-goals.pl"],
        "",
        "helloworld\n",
    )
}

// issue #815
#[test]
fn no_stutter() {
    run_top_level_test_no_args("write(a), write(b), false.\n", "ab   false.\n")
}

// issue #812
#[test]
#[ignore] // FIXME: line is of by one, empty line not accounted for or starting to count at line 0?
fn singleton_warning() {
    run_top_level_test_no_args(
        "['tests-pl/issue812-singleton-warning.pl'].",
        "\
        Warning: singleton variables X at line 4 of issue812-singleton-warning.pl\n   \
        true.\n\
        ",
    );
}

// issue #807
#[test]
fn ignored_constraint() {
    run_top_level_test_no_args(
        "use_module(library(freeze)), freeze(X,false), X \\=a.",
        "   freeze:freeze(X,user:false).\n",
    );
}

// issue #831
#[test]
fn call_0() {
    load_module_test(
        "tests-pl/issue831-call0.pl",
        "caught: error(existence_error(procedure,call/0),call/0)\n",
    );
}
