use prolog::heap_iter::*;
use prolog::machine::*;

use std::collections::HashSet;
use std::collections::hash_set::IntoIter;

pub static VERIFY_ATTRS: &str  = include_str!("attributed_variables.pl");
pub static PROJECT_ATTRS: &str = include_str!("project_attributes.pl");

pub(super) type Bindings = Vec<(usize, Addr)>;

pub(super) struct AttrVarInitializer {
    pub(super) attribute_goals: Vec<Addr>,
    pub(super) bindings: Bindings,
    pub(super) cp: LocalCodePtr,
    pub(super) verify_attrs_loc: usize,
    pub(super) project_attrs_loc: usize,
}

impl AttrVarInitializer {
    pub(super) fn new(verify_attrs_loc: usize, project_attrs_loc: usize) -> Self {
        AttrVarInitializer {
            attribute_goals: vec![],
            bindings: vec![],
            cp: LocalCodePtr::default(),
            verify_attrs_loc,
            project_attrs_loc
        }
    }

    #[inline]
    pub(super) fn reset(&mut self) {
        self.bindings.clear();
    }
}

impl MachineState {
    pub(super) fn push_attr_var_binding(&mut self, h: usize, addr: Addr)
    {
        if self.attr_var_init.bindings.is_empty() {
            self.attr_var_init.cp = self.p.local();
            self.p = CodePtr::VerifyAttrInterrupt(self.attr_var_init.verify_attrs_loc);
        }

        self.attr_var_init.bindings.push((h, addr));
    }

    fn populate_var_and_value_lists(&mut self) -> (Addr, Addr) {
        let iter = self.attr_var_init.bindings.iter().map(|(ref h, _)| Addr::AttrVar(*h));
        let var_list_addr = Addr::HeapCell(self.heap.to_list(iter));

        let iter = self.attr_var_init.bindings.iter().map(|(_, ref addr)| addr.clone());
        let value_list_addr = Addr::HeapCell(self.heap.to_list(iter));

        (var_list_addr, value_list_addr)
    }

    pub(super)
    fn calculate_register_threshold(&self) -> usize {
        let mut count = 0;

        for r in 1 .. MAX_ARITY + 1 {
            if let &Addr::HeapCell(0) = &self[RegType::Temp(r)] {
                break;
            }

            count += 1;
        }

        count
    }

    pub(super)
    fn verify_attributes(&mut self)
    {
        for (h, _) in &self.attr_var_init.bindings {
            self.heap[*h] = HeapCellValue::Addr(Addr::AttrVar(*h));
        }

        let (var_list_addr, value_list_addr) = self.populate_var_and_value_lists();

        self[temp_v!(1)] = var_list_addr;
        self[temp_v!(2)] = value_list_addr;
    }

    fn gather_attr_vars_created_since(&self, h: usize) -> IntoIter<Addr> {
        let mut attr_vars = HashSet::new();

        for i in h .. self.heap.h {
            let addr = self.heap[i].as_addr(i);

            match addr {
                Addr::AttrVar(h) if i == h => {
                    attr_vars.insert(Addr::AttrVar(h));
                },
                _ => {}
            }
        }

        attr_vars.into_iter()
    }

    fn populate_project_attr_lists(&mut self, var_dict: &HeapVarDict) -> (Addr, Addr)
    {
        let mut query_vars = HashSet::new();
        let attr_vars = self.gather_attr_vars_created_since(0);

        for (_, addr) in var_dict {
            let iter = HCPreOrderIterator::new(&self, addr.clone());

            for value in iter {
                match value {
                    HeapCellValue::Addr(Addr::HeapCell(h)) => {
                        query_vars.insert(Addr::HeapCell(h));
                    },
                    HeapCellValue::Addr(Addr::StackCell(fr, sc)) => {
                        query_vars.insert(Addr::StackCell(fr, sc));
                    },
                    _ => {}
                };
            }
        }

        let query_var_list = Addr::HeapCell(self.heap.to_list(query_vars.into_iter()));
        let attr_var_list  = Addr::HeapCell(self.heap.to_list(attr_vars));

        (query_var_list, attr_var_list)
    }

    pub(super)
    fn verify_attr_interrupt(&mut self, p: usize) {
        let rs = self.calculate_register_threshold();

        // store temp vars in perm vars slots along with
        // self.b0 and self.num_of_args. why self.bo? if we return to a
        // NeckCut after finishing the interrupt, it won't
        // work correctly if self.b == self.b0. we must
        // change it back when we return, as if nothing happened.
        self.allocate(rs + 2);

        let e = self.e;
        self.and_stack[e].special_form_cp = self.attr_var_init.cp;

        for i in 1 .. rs + 1 {
            self.and_stack[e][i] = self[RegType::Temp(i)].clone();
        }

        self.and_stack[e][rs + 1] = Addr::Con(Constant::Usize(self.b0));
        self.and_stack[e][rs + 2] = Addr::Con(Constant::Usize(self.num_of_args));

        self.verify_attributes();

        self.num_of_args = 2;
        self.b0 = self.b;
        self.p = CodePtr::Local(LocalCodePtr::DirEntry(p));
    }

    fn print_attribute_goals(&mut self, var_dict: &HeapVarDict)
    {
        let attr_goals = mem::replace(&mut self.attr_var_init.attribute_goals, vec![]);

        if attr_goals.is_empty() {
            return;
        }

        let mut output = PrinterOutputter::new();

        for goal_addr in attr_goals {
            let mut printer = HCPrinter::from_heap_locs(&self, output, var_dict);
            printer.see_all_locs();

            printer.numbervars = false;
            printer.quoted = true;

            output = printer.print(goal_addr);
            output.append(", ");
        }

        // cut trailing ", "
        let output_len = output.len();
        output.truncate(output_len - 2);

        println!("\r\n{}\r", output.result());
    }
}

impl Machine {
    pub
    fn attribute_goals(&mut self, var_dict: &HeapVarDict)
    {
        let p = self.machine_st.attr_var_init.project_attrs_loc;
        let (query_vars, attr_vars) = self.machine_st.populate_project_attr_lists(var_dict);

        self.machine_st.allocate(0);

        self.machine_st[temp_v!(1)] = query_vars;
        self.machine_st[temp_v!(2)] = attr_vars;

        self.machine_st.p = CodePtr::Local(LocalCodePtr::DirEntry(p));
        self.machine_st.query_stepper(&mut self.indices, &mut self.policies, &mut self.code_repo);

        self.machine_st.print_attribute_goals(var_dict);
    }
}